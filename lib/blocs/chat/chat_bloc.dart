import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nmobile/blocs/chat/chat_event.dart';
import 'package:nmobile/blocs/chat/chat_state.dart';
import 'package:nmobile/blocs/contact/contact_bloc.dart';
import 'package:nmobile/blocs/contact/contact_event.dart';
import 'package:nmobile/blocs/nkn_client_caller.dart';
import 'package:nmobile/helpers/global.dart';
import 'package:nmobile/helpers/hash.dart';
import 'package:nmobile/helpers/local_storage.dart';
import 'package:nmobile/helpers/utils.dart';
import 'package:nmobile/model/datacenter/contact_data_center.dart';
import 'package:nmobile/model/datacenter/group_data_center.dart';
import 'package:nmobile/model/datacenter/message_data_center.dart';
import 'package:nmobile/model/entity/subscriber_repo.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/model/message_model.dart';
import 'package:nmobile/plugins/nkn_wallet.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/group_chat_helper.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/utils/log_tag.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:path/path.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> with Tag {
  @override
  ChatState get initialState => NoConnectState();
  final ContactBloc contactBloc;

  ChatBloc({@required this.contactBloc});

  /// This variable used to Check If the AndroidDevice got FCM Ability
  /// If so,there is no need to alert Notification while in ForegroundState by Android Device
  bool googleServiceOn = false;
  bool googleServiceOnInit = false;

  Timer watchDog;
  int delayReceivingSeconds = 2;
  List<MessageSchema> batchReceivedList = new List();

  // int delayResendSeconds = 15;
  // Map judgeToResendMessage = new Map();

  Uint8List messageIn, messageOut;

  int perPieceLength = (1024 * 8);
  int maxPieceCount = 25;

  bool groupUseOnePiece = true;

  @override
  Stream<ChatState> mapEventToState(ChatEvent event) async* {
    if (event is NKNChatOnMessageEvent) {
      yield OnConnectState();
    } else if (event is ReceiveMessageEvent) {
      yield* _mapReceiveMessageToState(event);
    } else if (event is SendMessageEvent) {
      NLog.w('SendMessageEvent called!!!');
      yield* _mapSendMessageToState(event);
    }
    else if (event is RefreshMessageListEvent) {
      var unReadCount = await MessageSchema.unReadMessages();
      FlutterAppBadger.updateBadgeCount(unReadCount);
      yield MessageUpdateState(target: event.targetId);
    } else if (event is RefreshMessageChatEvent) {
      MessageModel model = await MessageModel.modelFromMessageFrom(event.message);

      String targetId;
      if (event.message.topic != null && event.message.topic.length > 0){
        targetId = event.message.topic;
      }
      if (event.message.isSendMessage()){
        targetId = event.message.to;
      }
      else{
        targetId = event.message.from;
      }
      NLog.w('RefreshMessageChatEvent targetId is____'+targetId.toString());
      yield MessageUpdateState(target: targetId, message: model);
    }
  }

  _insertMessage(MessageSchema message) async {
    message.sendReceiptMessage();
    bool messageExist = await message.isReceivedMessageExist();
    if (messageExist == false){
      _startWatchDog(message);
    }
  }

  _startWatchDog(MessageSchema msg) {
    if (batchReceivedList == null){
      batchReceivedList = new List();
    }
    bool canAdd = true;
    if (batchReceivedList != null && batchReceivedList.length > 0){
      for (MessageSchema bMessage in batchReceivedList){
        if (bMessage.msgId == msg.msgId){
          canAdd = false;
        }
      }
    }
    if (canAdd){
      batchReceivedList.add(msg);
    }
    else{
      NLog.w('batchReceivedList duplicate add____'+msg.content.toString());
    }
    NLog.w('_startWatchDog batchReceivedList is____'+batchReceivedList.length.toString());

    if (watchDog == null || watchDog.isActive == false) {

      delayReceivingSeconds = 2;
      watchDog = Timer.periodic(Duration(milliseconds: 1000), (timer) async {
        _batchInsertReceivingMessage();
        delayReceivingSeconds--;
      });
    }
  }

  _batchInsertReceivingMessage() async{
    NLog.w('______!______'+delayReceivingSeconds.toString());
    if((delayReceivingSeconds == 0 && batchReceivedList.length > 0) ||
        batchReceivedList.length > 500){
      NLog.w('_batchInsertReceivingMessage count is____'+batchReceivedList.length.toString());
      await MessageDataCenter.batchInsertMessages(batchReceivedList);
      batchReceivedList.clear();
      _stopWatchDog();

      this.add(RefreshMessageListEvent());
    }
  }

  _stopWatchDog() {
    delayReceivingSeconds = 2;
    if (watchDog.isActive) {
      watchDog.cancel();
      watchDog = null;
    }
  }

  Stream<ChatState> _mapSendMessageToState(SendMessageEvent event) async* {
    var message = event.message;
    String contentData = '';
    await message.insertSendMessage();

    /// Handle GroupMessage Sending
    if (message.topic != null) {
      try {
        message.setMessageStatus(MessageStatus.MessageSending);
        _sendGroupMessage(message);
      } catch (e) {
        NLog.w('SendMessage Failed E:_____'+e.toString());
        message.setMessageStatus(MessageStatus.MessageSendFail);
      }

      MessageModel model = await MessageModel.modelFromMessageFrom(message);
      yield MessageUpdateState(target: message.to, message: model);
      return;
    }

    /// Handle SingleMessage Sending
    else {
      if (message.contentType == ContentType.text ||
          message.contentType == ContentType.textExtension ||
          message.contentType == ContentType.nknAudio ||
          message.contentType == ContentType.media ||
          message.contentType == ContentType.nknImage ||
          message.contentType == ContentType.channelInvitation) {

        if (message.burnAfterSeconds != null){
          if (message.burnAfterSeconds > 0) {
            message.deleteTime = DateTime.now()
                .add(Duration(seconds: message.burnAfterSeconds));
            await message.updateDeleteTime();
          }
        }
        _checkIfSendNotification(message.to, '');
        if (message.contentType == ContentType.text ||
            message.contentType == ContentType.textExtension ||
            message.contentType == ContentType.channelInvitation) {
          contentData = message.toTextData();
        }
        else{
          bool useOnePiece = false;
          String key = LocalStorage.NKN_ONE_PIECE_READY_JUDGE + message.to;
          String onePieceReady = await LocalStorage().get(key);

          if (onePieceReady != null && onePieceReady.length > 0) {
            useOnePiece = true;
            NLog.w('useOnePiece Send!!!!!!');
          }
          if (useOnePiece &&
              (message.contentType == ContentType.nknAudio ||
                  message.contentType == ContentType.media ||
                  message.contentType == ContentType.nknImage)) {
            _sendOnePieceMessage(message);
            return;
          } else {
            if (message.contentType == ContentType.media ||
                message.contentType == ContentType.nknImage ||
                message.contentType == ContentType.nknAudio ){
              NLog.w('SendDestination is+____'+message.to.length.toString());
              /// Consider it is D-ChatPC
              if (message.to.length > 64){
                String dataForDChatPC = message.toDChatMediaData(message.contentType);
                try {
                  Uint8List pid = await NKNClientCaller.sendText(
                      [message.to], dataForDChatPC, message.msgId);
                  if(pid != null){
                    message.setMessageStatus(MessageStatus.MessageSendSuccess);
                    MessageDataCenter.updateMessagePid(pid, message.msgId);
                  }
                  NLog.w('dataForDChatPC___'+pid.toString());
                } catch (e) {
                  NLog.w('Wrong___' + e.toString());
                  message.setMessageStatus(MessageStatus.MessageSendFail);
                }
                return;
              }
              else{
                if (message.contentType == ContentType.media ||
                    message.contentType == ContentType.nknImage){
                  contentData = message.toImageData();
                }
                else if (message.contentType == ContentType.nknAudio){
                  contentData = message.toAudioData();
                }
              }
            }
          }
        }
      } else if (message.contentType == ContentType.nknOnePiece) {
        contentData = message.toNknPieceMessageData();
      } else if (message.contentType == ContentType.eventContactOptions) {
        contentData = message.content;
      }

      NLog.w('ContentData is_____'+contentData.toString());

      try {
        if (contentData == null || contentData.length == 0){
          return;
        }
        Uint8List pid = await NKNClientCaller.sendText(
            [message.to], contentData, message.msgId);
        if(pid != null){
          message.setMessageStatus(MessageStatus.MessageSendSuccess);
          MessageDataCenter.updateMessagePid(pid, message.msgId);
          NLog.w('Pid is_____'+pid.toString());
        }
      } catch (e) {
        NLog.w('Wrong___' + e.toString());
        message.setMessageStatus(MessageStatus.MessageSendFail);
      }
    }

    MessageModel model = await MessageModel.modelFromMessageFrom(message);
    yield MessageUpdateState(target: message.to, message: model);
  }

  _combineOnePieceMessage(MessageSchema onePieceMessage) async {
    bool exist = await onePieceMessage.existOnePieceIndex();
    if (exist) {
      return;
    }

    Uint8List bytes = base64Decode(onePieceMessage.content);

    if (bytes.length > perPieceLength) {
      perPieceLength = bytes.length;
    }
    String name = hexEncode(md5.convert(bytes).bytes);

    String path = getCachePath(NKNClientCaller.currentChatId);
    name = onePieceMessage.msgId + '-nkn-' + name;

    String filePath =
        join(path, name + '.' + onePieceMessage.parentType.toString());
    NLog.w('FileLength is____' + bytes.length.toString());
    File file = File(filePath);

    file.writeAsBytesSync(bytes, flush: true);

    onePieceMessage.content = file;
    onePieceMessage.options = {
      'parity': onePieceMessage.parity,
      'total': onePieceMessage.total,
      'index': onePieceMessage.index,
      'parentType': onePieceMessage.parentType,
      'deleteAfterSeconds': onePieceMessage.burnAfterSeconds,
      'audioDuration': onePieceMessage.audioFileDuration,
    };
    await onePieceMessage.insertOnePieceMessage();

    int total = onePieceMessage.total;

    List allPieces = await onePieceMessage.allPieces();

    bool existFull = await onePieceMessage.existFullPiece();
    if (existFull) {
      NLog.w(
          '_combineOnePieceMessage existOnePiece___' + onePieceMessage.msgId);
      return;
    }

    if (allPieces.length == total) {
      NLog.w('onePieceMessage total is___\n' +
          onePieceMessage.total.toString() +
          'parity is__' +
          onePieceMessage.parity.toString());
      NLog.w('onePieceMessage bytesLength is___' +
          onePieceMessage.bytesLength.toString());

      File eFile = onePieceMessage.content as File;
      int pLength = eFile.readAsBytesSync().length;
      int shardTotal = onePieceMessage.total + onePieceMessage.parity;

      shardTotal = onePieceMessage.total + onePieceMessage.parity;

      // shardTotal = 13;

      List recoverList = new List();
      for (int i = 0; i < shardTotal; i++) {
        MessageSchema onePiece;
        for (MessageSchema schema in allPieces) {
          if (schema.index == i) {
            onePiece = schema;
          }
        }
        if (onePiece != null) {
          File oneFile = onePiece.content as File;
          Uint8List fBytes = oneFile.readAsBytesSync();
          recoverList.add(fBytes);
          NLog.w('Fill fBytes ___' +
              fBytes
                  .getRange(fBytes.length ~/ 2, fBytes.length - 1)
                  .toString());
        } else {
          recoverList.add(Uint8List(0));
          NLog.w('Fill EmptyList ___' + i.toString());
        }
      }

      if (recoverList.length < onePieceMessage.total) {
        NLog.w('Wrong!!!! recoverList is too short!');
        return;
      }

      String recoverString = await NKNClientCaller.combinePieces(
          recoverList,
          onePieceMessage.total,
          onePieceMessage.parity,
          onePieceMessage.bytesLength);

      NLog.w('recoverString length is___' + recoverString.length.toString());
      Uint8List fBytes;
      try {
        fBytes = base64Decode(recoverString);
      } catch (e) {
        NLog.w('Base64Decode Error:' + e.toString());
      }

      NLog.w('Step4__  fBytes   ' + fBytes.length.toString());
      String name = hexEncode(md5.convert(fBytes).bytes);
      name = onePieceMessage.msgId + '-nkn-' + name;

      String extension = 'media';
      if (onePieceMessage.parentType == ContentType.nknAudio) {
        extension = 'aac';
      }

      String fullPath = getCachePath(NKNClientCaller.currentChatId);
      File fullFile = File(join(fullPath, name + '$extension'));
      fullFile.writeAsBytes(fBytes, flush: true);

      MessageSchema nReceived = MessageSchema.formReceivedMessage(
        topic: onePieceMessage.topic,
        msgId: onePieceMessage.msgId,
        from: onePieceMessage.from,
        to: onePieceMessage.to,
        pid: onePieceMessage.pid,
        contentType: onePieceMessage.parentType,
        content: fullFile,
        audioFileDuration: onePieceMessage.audioFileDuration,
        timestamp: onePieceMessage.timestamp,
      );
      if (onePieceMessage.options != null){
        nReceived.options = onePieceMessage.options;
        if (nReceived.options['deleteAfterSeconds'] != null){
          nReceived.burnAfterSeconds = int.parse(nReceived.options['deleteAfterSeconds'].toString());
        }
      }

      await nReceived.insertReceivedMessage();

      nReceived.setMessageStatus(MessageStatus.MessageReceived);
      nReceived.sendReceiptMessage();

      MessageDataCenter.removeOnePieceCombinedMessage(nReceived.msgId);

      this.add(RefreshMessageChatEvent(nReceived));
    }
  }

  _sendOnePiece(List mpList, MessageSchema parentMessage) async {
    for (int index = 0; index < mpList.length; index++) {
      Uint8List fileP = mpList[index];

      int deleteAfterSeconds;
      if (parentMessage.topic == null){
        ContactSchema contact = await _checkContactIfExists(parentMessage.to);
        if (contact?.options != null) {
          if (contact?.options?.deleteAfterSeconds != null) {
            deleteAfterSeconds = contact.options.deleteAfterSeconds;
          }
        }
      }
      String content = base64Encode(fileP);

      NLog.w('Send OnePiece with Content__' +
          index.toString() +
          '__' +
          parentMessage.bytesLength.toString());

      String toValue;
      String topicValue;
      if (parentMessage.topic != null && parentMessage.topic.length > 0){
        topicValue = parentMessage.topic;
        toValue = null;
      }
      else{
        toValue = parentMessage.to;
      }
      Duration duration = Duration(milliseconds: index * 10);

      Timer(duration, () async {
        var nknOnePieceMessage = MessageSchema.formSendMessage(
          msgId: parentMessage.msgId,
          from: parentMessage.from,
          to: toValue,
          topic: topicValue,
          parentType: parentMessage.contentType,
          content: content,
          contentType: ContentType.nknOnePiece,
          parity: parentMessage.parity,
          total: parentMessage.total,
          index: index,
          bytesLength: parentMessage.bytesLength,
          burnAfterSeconds: deleteAfterSeconds,
          audioFileDuration: parentMessage.audioFileDuration,
        );
        NLog.w('Send OnePiece with index__' +
            index.toString() +
            '__' +
            parentMessage.bytesLength.toString());
        this.add(SendMessageEvent(nknOnePieceMessage));
      });
    }
  }

  _sendOnePieceMessage(MessageSchema message) async {
    File file = message.content as File;

    Uint8List fileBytes = file.readAsBytesSync();
    String base64Content = base64.encode(fileBytes);

    int total = 10;
    int parity = total ~/ 3;
    if (base64Content.length <= perPieceLength) {
      total = 1;
      parity = 1;
    } else if (base64Content.length > perPieceLength &&
        base64Content.length < 25 * perPieceLength) {
      total = base64Content.length ~/ perPieceLength;
      if (base64Content.length % perPieceLength > 0) {
        total += 1;
      }
      parity = total ~/ 3;
    } else {
      total = maxPieceCount;
      parity = total ~/ 3;
    }
    if (parity == 0) {
      parity = 1;
    }

    message.total = total;
    message.parity = parity;
    message.bytesLength = base64Content.length;

    var dataList =
        await NKNClientCaller.intoPieces(base64Content, total, parity);
    NLog.w('_sendOnePieceMessage__Length__' + dataList.length.toString());
    _sendOnePiece(dataList, message);
  }

  _sendGroupMessage(MessageSchema message) async {
    if (message.contentType == ContentType.text ||
        message.contentType == ContentType.textExtension ||
        message.contentType == ContentType.nknAudio ||
        message.contentType == ContentType.media ||
        message.contentType == ContentType.nknImage ||
        message.contentType == ContentType.channelInvitation) {
      if (message.options != null &&
          message.options['deleteAfterSeconds'] != null) {
        message.deleteTime = DateTime.now()
            .add(Duration(seconds: message.options['deleteAfterSeconds']));
        await message.updateDeleteTime();
      }

      List<Subscriber> groupMembers =
      await GroupDataCenter.fetchSubscribedMember(message.topic);
      for (Subscriber sub in groupMembers){
        _checkIfSendNotification(sub.chatId, '');
      }
    }

    String encodeSendJsonData;
    if (message.contentType == ContentType.text) {
      encodeSendJsonData = message.toTextData();
    } else if (message.contentType == ContentType.nknImage ||
        message.contentType == ContentType.media) {
      encodeSendJsonData = message.toImageData();
    } else if (message.contentType == ContentType.nknAudio) {
      encodeSendJsonData = message.toAudioData();
    } else if (message.contentType == ContentType.eventSubscribe) {
      encodeSendJsonData = message.toEventSubscribeData();
    } else if (message.contentType == ContentType.eventUnsubscribe) {
      encodeSendJsonData = message.toEventUnSubscribeData();
    }
    if (groupUseOnePiece){
      if (message.contentType == ContentType.text ||
          message.contentType == ContentType.eventSubscribe ||
          message.contentType == ContentType.eventUnsubscribe){
        _sendGroupMessageWithJsonEncode(message, encodeSendJsonData);
      }
      else if (message.contentType == ContentType.nknOnePiece){
        List<String> targets = await GroupDataCenter.fetchGroupMembersTargets(message.topic);

        List<String> onePieceTargets = new List<String>();
        for (String targetId in targets){
          String key = LocalStorage.NKN_ONE_PIECE_READY_JUDGE + targetId;
          String onePieceReady = await LocalStorage().get(key);
          if (onePieceReady != null && onePieceReady.length > 0) {
            onePieceTargets.add(targetId);
            NLog.w('onePieceReady Target is_______'+targetId.length.toString());
          }
        }

        String onePieceEncodeData = message.toNknPieceMessageData();
        if (onePieceTargets.length > 0) {
          Uint8List pid = await NKNClientCaller.sendText(
              onePieceTargets, onePieceEncodeData, message.msgId);
          message.setMessageStatus(MessageStatus.MessageSendSuccess);
          MessageDataCenter.updateMessagePid(pid, message.msgId);
        } else {
          if (message.topic != null) {
            NLog.w('Wrong !!!Topic got no Member' + message.topic);
          }
        }
      }
      else{
        _sendOnePieceMessage(message);
        _sendGroupMessageWithJsonEncode(message, encodeSendJsonData);
      }
    }
    else{
      _sendGroupMessageWithJsonEncode(message, encodeSendJsonData);
    }
  }

  _sendGroupMessageWithJsonEncode(MessageSchema message,String encodeJson) async{
    if (isPrivateTopicReg(message.topic)){
      List<String> targets = await GroupDataCenter.fetchGroupMembersTargets(message.topic);
      if (targets != null && targets.length > 0) {
        Uint8List pid = await NKNClientCaller.sendText(
            targets, encodeJson, message.msgId);
        message.setMessageStatus(MessageStatus.MessageSendSuccess);
        MessageDataCenter.updateMessagePid(pid, message.msgId);
      } else {
        if (message.topic != null) {
          NLog.w('Wrong !!!Topic got no Member' + message.topic);
        }
      }
    } else {
      /// do not use check send
      if (message.contentType == ContentType.text ||
          message.contentType == ContentType.eventSubscribe ||
          message.contentType == ContentType.eventUnsubscribe){
        Uint8List pid;
        try {
          pid = await NKNClientCaller.publishText(
              genTopicHash(message.topic), encodeJson);
          message.setMessageStatus(MessageStatus.MessageSendSuccess);
        } catch (e) {
          message.setMessageStatus(MessageStatus.MessageSendFail);
          NLog.w('_sendGroupMessageWithJsonEncode E:'+e.toString());
        }
        if (pid != null) {
          MessageDataCenter.updateMessagePid(pid, message.msgId);
        }
      }
      else{
        Uint8List pid;
        try {
          List<String> targets = await GroupDataCenter.fetchGroupMembersTargets(message.topic);
          List<String> oldTargets = new List<String>();
          for (String targetId in targets){
            String key = LocalStorage.NKN_ONE_PIECE_READY_JUDGE + targetId;
            String onePieceReady = await LocalStorage().get(key);
            if (onePieceReady == null) {
              oldTargets.add(targetId);
            }
          }
          if (oldTargets != null && oldTargets.length > 0) {
            Uint8List pid = await NKNClientCaller.sendText(
                oldTargets, encodeJson, message.msgId);
            message.setMessageStatus(MessageStatus.MessageSendSuccess);
            MessageDataCenter.updateMessagePid(pid, message.msgId);
            NLog.w('SendTotal is______'+(oldTargets.length*encodeJson.length).toString());
          } else {
            if (message.topic != null) {
              NLog.w('Wrong !!!Topic got no Member' + message.topic);
            }
            else{
              NLog.w('Wrong !!!Message.topic is null');
            }
          }

        } catch (e) {
          message.setMessageStatus(MessageStatus.MessageSendFail);
          NLog.w('_sendGroupMessageWithJsonEncode E:'+e.toString());
        }
        if (pid != null) {
          MessageDataCenter.updateMessagePid(pid, message.msgId);
        }
      }
    }
  }

  Stream<ChatState> _mapReceiveMessageToState(
      ReceiveMessageEvent event) async* {
    var message = event.message;

    if (message.content.toString().contains('(_test_)')){
      NLog.w('Test Content is____'+message.content.toString());
    }
    /// judge if ReceivedMessage duplicated
    // if (messageExist == true) {
    //   /// should retry here!!!
    //   if (message.isSuccess == false &&
    //       message.contentType != ContentType.nknOnePiece) {
    //     message.sendReceiptMessage();
    //   }
    //   NLog.w('ReceiveMessage from AnotherNode__');
    //   return;
    // }
    // else{
    //   /// judge ReceiveMessage if D-Chat PC groupMessage Receipt
    //   MessageSchema dChatPcReceipt = await MessageSchema.findMessageWithMessageId(event.message.msgId);
    //   if (dChatPcReceipt != null && dChatPcReceipt.contentType != ContentType.nknOnePiece){
    //     dChatPcReceipt = await dChatPcReceipt.receiptMessage();
    //
    //     dChatPcReceipt.content = message.msgId;
    //     dChatPcReceipt.contentType = ContentType.receipt;
    //     dChatPcReceipt.topic = null;
    //
    //     MessageModel model = await MessageModel.modelFromMessageFrom(dChatPcReceipt);
    //     yield MessageUpdateState(target: dChatPcReceipt.from, message: model);
    //     return;
    //   }
    // }

    if (message.contentType == ContentType.receipt) {
      MessageSchema oMessage = await message.receiptMessage();
      if (oMessage != null){

        oMessage.content = oMessage.msgId;
        oMessage.contentType = ContentType.receipt;
        oMessage.topic = null;

        MessageModel model = await MessageModel.modelFromMessageFrom(oMessage);
        yield MessageUpdateState(target: oMessage.from, message: model);
        return;
      }
    }

    ContactSchema contact = await _checkContactIfExists(message.from);
    if (!contact.isMe &&
        message.contentType != ContentType.contact &&
        Global.isLoadProfile(contact.publicKey)) {
      if (contact.profileExpiresAt == null ||
          DateTime.now().isAfter(contact.profileExpiresAt)) {
        Global.saveLoadProfile(contact.publicKey);

        ContactDataCenter.requestProfile(contact, RequestType.header);
      }
    }

    if (message.contentType == ContentType.text ||
        message.contentType == ContentType.textExtension ||
        message.contentType == ContentType.nknAudio ||
        message.contentType == ContentType.nknImage ||
        message.contentType == ContentType.media ||
        message.contentType == ContentType.eventContactOptions ||
        message.contentType == ContentType.eventSubscribe ||
        message.contentType == ContentType.eventUnsubscribe ||
        message.contentType == ContentType.channelInvitation) {
      /// If Received self Send
      if (message.from == NKNClientCaller.currentChatId) {
        MessageSchema oMessage = await message.receiptMessage();

        MessageModel model = await MessageModel.modelFromMessageFrom(oMessage);
        yield MessageUpdateState(target: oMessage.from, message: model);
        return;
      }
      else {
        if (message.contentType == ContentType.eventSubscribe ||
            message.contentType == ContentType.eventUnsubscribe) {
          if (message.from == NKNClientCaller.currentChatId) {} else {
            if (message.topic != null) {
              if (isPrivateTopicReg(message.topic)) {
                // todo Update Private Group Member Later.
                // GroupDataCenter.pullPrivateSubscribers(message.topic);
              } else {
                if (message.contentType == ContentType.eventSubscribe){
                  // add Member
                  Subscriber sub = Subscriber(
                      id: 0,
                      topic: message.topic,
                      chatId: message.from,
                      indexPermiPage: -1,
                      timeCreate: DateTime.now().millisecondsSinceEpoch,
                      blockHeightExpireAt: -1,
                      memberStatus: MemberStatus.MemberSubscribed);

                  SubscriberRepo().insertSubscriber(sub);
                }
                else if (message.contentType == ContentType.eventUnsubscribe){
                  // delete Member
                  GroupChatHelper.deleteSubscriberOfTopic(message.topic, message.from);
                }
                GroupDataCenter.pullSubscribersPublicChannel(message.topic);
              }
            }
          }
        }
        _insertMessage(message);
      }
    }

    /// Media Message
    if (message.contentType == ContentType.nknAudio ||
        message.contentType == ContentType.nknImage ||
        message.contentType == ContentType.media) {
      message.loadMedia();
    }

    if (message.topic != null) {
      /// Group Message
      if (message.contentType == ContentType.nknOnePiece) {
        NLog.w('Received nknOnePiece topic__'+message.topic.toString());
        _combineOnePieceMessage(message);
        return;
      }
      Topic topic = await GroupChatHelper.fetchTopicInfoByName(message.topic);
      if (topic == null) {
        bool meInChannel = await GroupChatPublicChannel.checkMeInChannel(
            message.topic, NKNClientCaller.currentChatId);
        NLog.w('Me in Channel is___'+meInChannel.toString());
        GroupDataCenter.pullSubscribersPublicChannel(message.topic);
        if (meInChannel == false) {
          return;
        } else {
          await GroupChatHelper.insertTopicIfNotExists(message.topic);
        }
      } else {
        bool existMember = await GroupChatHelper.checkMemberIsInGroup(
            message.from, message.topic);
        NLog.w('Exist no Member___' + existMember.toString());
        NLog.w('Exist no Member___' + message.from.toString());
        if (existMember == false) {
          /// insertMember
          /// do private logic
          if (topic.isPrivateTopic()){

          }
          else{
            Subscriber sub = Subscriber(
                id: 0,
                topic: message.topic.toString(),
                chatId: message.from.toString(),
                indexPermiPage: -1,
                timeCreate: DateTime.now().millisecondsSinceEpoch,
                blockHeightExpireAt: -1,
                memberStatus: MemberStatus.MemberSubscribed);

            SubscriberRepo().insertSubscriber(sub);
            await GroupDataCenter.pullSubscribersPublicChannel(message.topic);
          }
        }
      }
    }
    else {
      /// Single Message
      var contact = await _checkContactIfExists(message.from);
      if (message.contentType == ContentType.text ||
          message.contentType == ContentType.textExtension ||
          message.contentType == ContentType.media ||
          message.contentType == ContentType.nknImage ||
          message.contentType == ContentType.nknAudio) {
        // message.sendReceiptMessage();
        _checkBurnOptions(message, contact);
      } else if (message.contentType == ContentType.nknOnePiece) {
        _combineOnePieceMessage(message);
        return;
      }

      /// Operation Message
      else if (message.contentType == ContentType.contact) {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(message.content);
        } on FormatException catch (e) {
          NLog.w('ContentType.contact Wrong!' + e.toString());
        }

        /// Receive Contact Request
        if (data['requestType'] != null) {
          ContactDataCenter.meResponseToProfile(contact, data);
        }

        /// Receive Contact Response
        else {
          if (data['onePieceReady'] != null) {
            String key = LocalStorage.NKN_ONE_PIECE_READY_JUDGE + message.from;
            LocalStorage().set(key, 'YES');
          }
          if (data['version'] == null) {
            NLog.w(
                'Unexpected Profile__No profile_version__' + data.toString());
          } else {
            /// do not have his contact
            NLog.w('Current Contact ProfileVersion is___' +
                contact.profileVersion.toString());
            if (data['responseType'] == RequestType.header) {
              await ContactDataCenter.setOrUpdateProfileVersion(contact, data);
            } else if (data['responseType'] == RequestType.full) {
              await contact.setOrUpdateExtraProfile(data);
              contactBloc.add(RefreshContactInfoEvent(contact.clientAddress));
            } else {
              /// fit Version before 1.1.0
              if (data['content'] != null &&
                  (data['content']['name'] != null ||
                      data['content']['avatar'] != null)) {
                await contact.setOrUpdateExtraProfile(data);
                contactBloc.add(RefreshContactInfoEvent(contact.clientAddress));
              } else {
                await ContactDataCenter.setOrUpdateProfileVersion(
                    contact, data);
              }
            }
          }
        }
      } else if (message.contentType == ContentType.eventContactOptions) {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(message.content);
        } on FormatException catch (e) {
          NLog.w('ContentType.eventContactOptions E:' + e.toString());
        }
        if (data['optionType'] == 0 || data['optionType'] == '0') {
          _checkBurnOptions(message, contact);
          await contact.setBurnOptions(data['content']['deleteAfterSeconds']);
        } else {
          await contact.setDeviceToken(data['content']['deviceToken']);
        }
        contactBloc.add(RefreshContactInfoEvent(contact.clientAddress));
      }
      else {
        NLog.w('Wrong!!! MessageType unhandled___' +
            message.contentType.toString());
      }
    }
    String targetId = '';
    if (message.topic != null && message.topic.length > 0){
      targetId = message.topic;
    }
    else{
      targetId = message.from;
    }

    message.setMessageStatus(MessageStatus.MessageReceived);
    MessageModel model = await MessageModel.modelFromMessageFrom(message);
    yield MessageUpdateState(target: targetId, message: model);
  }

  // Stream<ChatState> _mapGetAndReadMessagesToState(
  //     GetAndReadMessages event) async* {
  //   if (event.target != null) {
  //     MessageSchema.getAndReadTargetMessages(event.target);
  //   }
  //   NLog.w('From _mapGetAndReadMessagesToState');
  //   yield MessageUpdateState(target: event.target);
  // }

  /// change burn status
  _checkBurnOptions(MessageSchema message, ContactSchema contact) async {
    if (message.topic != null) return;

    if (message.burnAfterSeconds != null) {
      if (message.contentType != ContentType.eventContactOptions){
        if (contact.options == null){
          NLog.w('Wrong!!!!! _checkBurnOptions contact.options is null');
        }
        if (contact.options.updateBurnAfterTime == null ||
            message.timestamp.millisecondsSinceEpoch >
                contact.options.updateBurnAfterTime) {

          await contact.setBurnOptions(message.burnAfterSeconds);
        }
      }
    }
    NLog.w('!!!!contact._checkBurnOptions ___' +
        message.burnAfterSeconds.toString());
    contactBloc.add(RefreshContactInfoEvent(contact.clientAddress));
  }

  Future<ContactSchema> _checkContactIfExists(String clientAddress) async {
    var contact = await ContactSchema.fetchContactByAddress(clientAddress);
    if (contact == null) {
      /// need Test
      var walletAddress = await NknWalletPlugin.pubKeyToWalletAddr(
          getPublicKeyByClientAddr(clientAddress));

      if (clientAddress != null) {
        NLog.w('Insert contact stranger__' + clientAddress.toString());
      } else {
        NLog.w('got clientAddress Wrong!!!');
      }
      if (walletAddress == null) {
        NLog.w('got walletAddress Wrong!!!');
      }

      contact = ContactSchema(
          type: ContactType.stranger,
          clientAddress: clientAddress,
          nknWalletAddress: walletAddress);
      await contact.insertContact();
    }
    return contact;
  }

  /// check need send Notification
  Future<void> _checkIfSendNotification(String messageTo,String content) async {
    ContactSchema contact = await _checkContactIfExists(messageTo);

    String deviceToken = '';
    if (contact.deviceToken != null && contact.deviceToken.length > 0) {
      // String pushContent = NL10ns.of(Global.appContext).notification_push_content;
      String pushContent = 'New Message!';
      // pushContent = "from:"+accountChatId.substring(0, 8) + "...";
      // pushContent = 'You have New Message!';
      /// if no deviceToken means unable googleServiceOn is False
      /// GoogleServiceOn channel method can not be the judgement Because Huawei Device GoogleService is on true but not work!!!
      deviceToken = contact.deviceToken;
      if (deviceToken != null && deviceToken.length > 0) {
        NLog.w('Send Push notification content__' + deviceToken.toString());
        NKNClientCaller.nknPush(deviceToken,pushContent);
      }
    }
  }
}
