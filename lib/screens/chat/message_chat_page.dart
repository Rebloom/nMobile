import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nmobile/blocs/channel/channel_bloc.dart';
import 'package:nmobile/blocs/channel/channel_event.dart';
import 'package:nmobile/blocs/channel/channel_state.dart';
import 'package:nmobile/blocs/chat/chat_bloc.dart';
import 'package:nmobile/blocs/chat/chat_event.dart';
import 'package:nmobile/blocs/chat/chat_state.dart';
import 'package:nmobile/blocs/contact/contact_bloc.dart';
import 'package:nmobile/blocs/message/message_bloc.dart';
import 'package:nmobile/blocs/message/message_event.dart';
import 'package:nmobile/blocs/nkn_client_caller.dart';
import 'package:nmobile/components/CommonUI.dart';
import 'package:nmobile/components/box/body.dart';
import 'package:nmobile/components/button.dart';
import 'package:nmobile/components/button_icon.dart';
import 'package:nmobile/components/chat/bubble.dart';
import 'package:nmobile/components/chat/system.dart';
import 'package:nmobile/components/header/header.dart';
import 'package:nmobile/components/label.dart';
import 'package:nmobile/components/layout/expansion_layout.dart';
import 'package:nmobile/consts/theme.dart';
import 'package:nmobile/helpers/format.dart';
import 'package:nmobile/helpers/global.dart';
import 'package:nmobile/helpers/hash.dart';
import 'package:nmobile/helpers/local_storage.dart';
import 'package:nmobile/helpers/nkn_image_utils.dart';
import 'package:nmobile/helpers/utils.dart';
import 'package:nmobile/l10n/localization_intl.dart';
import 'package:nmobile/model/datacenter/group_data_center.dart';
import 'package:nmobile/model/datacenter/message_data_center.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/group_chat_helper.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/model/message_model.dart';
import 'package:nmobile/screens/chat/channel_members.dart';
import 'package:nmobile/screens/chat/record_audio.dart';
import 'package:nmobile/screens/contact/contact.dart';
import 'package:nmobile/screens/settings/channel.dart';
import 'package:nmobile/screens/view/dialog_confirm.dart';
import 'package:nmobile/utils/extensions.dart';
import 'package:nmobile/utils/image_utils.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vibration/vibration.dart';

class MessageChatPage extends StatefulWidget {
  static const String routeName = '/chat/screen';

  var arguments;

  MessageChatPage(this.arguments);

  @override
  _MessageChatPageState createState() => _MessageChatPageState();
}

class _MessageChatPageState extends State<MessageChatPage> {
  ChatBloc _chatBloc;
  ContactBloc _contactBloc;
  ChannelBloc _channelBloc;
  MessageBloc _messageBloc;

  Topic topicInfo;
  ContactSchema contactInfo;

  String targetId;
  StreamSubscription _chatSubscription;
  ScrollController _scrollController = ScrollController();
  FocusNode _sendFocusNode = FocusNode();
  TextEditingController _sendController = TextEditingController();
  List<MessageModel> _messages = <MessageModel>[];
  bool _canSend = false;

  int startIndex = 0;

  bool loading = false;
  bool _showBottomMenu = false;
  Timer _deleteTick;
  Timer refreshSubscribersTimer;
  int _topicCount;

  bool showJoin = true;

  bool _acceptNotification = false;
  Color notiBellColor;
  static const fcmGapString = '__FCMToken__:';

  bool _showAudioInput = false;
  RecordAudio _recordAudio;
  DateTime cTime;
  bool _showAudioLock = false;
  double _audioLockHeight = 90;
  bool _audioLongPressEndStatus = false;

  initAsync() async {
    var res = await MessageDataCenter.getAndReadTargetMessages(targetId, 0);
    if (res != null) {
      setState(() {
        _messages = res;
        startIndex = _messages.length;
      });
    }
    if (topicInfo != null){
      refreshTop(topicInfo.topic);
    }
  }

  String genTopicHash(String topic) {
    if (topic == null || topic.isEmpty) {
      return null;
    }
    var t = unleadingHashIt(topic);
    return 'dchat' + hexEncode(sha1(t));
  }

  _updatePrivateTopicBlockHeight(Topic topic) async{
    NLog.w('_updatePrivateTopicBlockHeight  blockHeightExpireAt is___'+topic.blockHeightExpireAt.toString());
    if (topic.blockHeightExpireAt == null || topic.blockHeightExpireAt == -1){
      NLog.w('blockHeightExpireAt null or wrong!!!');
      String topicHash = genTopicHash(topic.topicName);

      var subscriptionInfo = await NKNClientCaller.getSubscription(
        topicHash: topicHash,
        subscriber: NKNClientCaller.currentChatId,
      );
      if (subscriptionInfo['expiresAt'] != null) {
        TopicRepo().updateOwnerExpireBlockHeight(topic.topicName,
            int.parse(subscriptionInfo['expiresAt'].toString()));
        NLog.w('UpgradeTopic__' +
            topic.topic +
            'Success' +
            '__' +
            subscriptionInfo.toString());
      }
    }
    else {
      int blockHeight = await NKNClientCaller.fetchBlockHeight();
      NLog.w('_updatePrivateTopicBlockHeight  blockHeight is___'+blockHeight.toString());
      NLog.w('topic.blockHeightExpireAt  blockHeight is___'+topic.blockHeightExpireAt.toString());
      if ((blockHeight-topic.blockHeightExpireAt) > Global.topicBlockHeightExpireWarnHeight) {
        GroupDataCenter.subscribeTopic(
            topicName: topic.topic,
            chatBloc: _chatBloc,
            callback: (success, e) {
              if (success) {
                NLog.w('update topic blockHeight success');
              } else {
                NLog.w('update topic blockHeight Failed E:' +
                    e.toString());
              }
            });
        GroupDataCenter.groupOwnerUpdatePermissionData(topic.topic);
      }
    }
  }

  refreshTop(String topicName) async {
    if (topicName != null) {
      NLog.w('refreshTop topic Name__' + topicName);
    }
    Topic topic = await GroupChatHelper.fetchTopicInfoByName(topicName);
    if (topic != null){
      if (topic.isPrivateTopic()) {
        NLog.w('Enter Private Topic___'+topicName);
        /// check if in group
        bool isMeInGroup = await GroupDataCenter.checkMeIn(topicName);
        NLog.w('isMeInGroup is_____'+isMeInGroup.toString());
        setState(() {
          showJoin = isMeInGroup;
        });
        await GroupDataCenter.pullPrivateSubscribers(topic.topic);
        String owner = getPubkeyFromTopicOrChatId(topicName);
        if (owner == NKNClientCaller.currentChatId) {
          _updatePrivateTopicBlockHeight(topic);
        }
        _channelBloc.add(ChannelMemberCountEvent(topicInfo.topic));
      }
      else{
        NLog.w('Enter Public Topic___'+topicName);
        GroupDataCenter.pullSubscribersPublicChannel(topic.topic);
      }
    }
    return;
  }

  Future _loadMore() async {
    if (_messages == null){
      startIndex = 0;
    }
    else{
      startIndex = _messages.length;
    }
    var res = await MessageDataCenter.getAndReadTargetMessages(targetId, startIndex);
    if (res == null) {
      return;
    }

    NLog.w('LoadMore called');

    _chatBloc.add(RefreshMessageListEvent(targetId: targetId));
    if (res != null) {
      startIndex += res.length;
      setState(() {
        _messages.addAll(res);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.arguments.runtimeType.toString() == 'ContactSchema'){
      contactInfo = widget.arguments;
      targetId = contactInfo.clientAddress;

      _acceptNotification = false;
      if (contactInfo.notificationOpen != null) {
        _acceptNotification = contactInfo.notificationOpen;
      }
    }
    else{
      topicInfo = widget.arguments;
      targetId = topicInfo.topic;
    }
    Global.currentOtherChatId = targetId;

    _contactBloc = BlocProvider.of<ContactBloc>(context);
    _chatBloc = BlocProvider.of<ChatBloc>(context);
    _channelBloc = BlocProvider.of<ChannelBloc>(context);
    _messageBloc = BlocProvider.of<MessageBloc>(context);

    _chatBloc.add(RefreshMessageListEvent(targetId: targetId));

    if (topicInfo != null){
      _channelBloc.add(ChannelMemberCountEvent(topicInfo.topicName));
    }

    _deleteTickHandle();

    Future.delayed(Duration(milliseconds: 200), () {
      initAsync();
      _sendFocusNode.addListener(() {
        if (_sendFocusNode.hasFocus) {
          setState(() {
            _showBottomMenu = false;
          });
        }
      });

      _chatSubscription = _chatBloc.listen((state) {
        if (state is MessageUpdateState && mounted) {
          if (state.message == null){
            return;
          }
          MessageModel updateModel = state.message;
          MessageSchema updateMessage = updateModel.messageEntity;
          if (updateMessage == null){
            return;
          }

          NLog.w('UpdateMessage is_____'+updateMessage.contentType.toString());
          for (MessageModel model in _messages){
            MessageSchema message = model.messageEntity;
            /// return of self send Message
            if (message.msgId == updateMessage.msgId && updateMessage.contentType != ContentType.receipt){
              NLog.w('return of self send Message___'+message.content.toString());
              return;
            }
          }
          if (state.target != null && updateMessage.contentType != ContentType.receipt){
            if (state.target != targetId){
              /// return of targetId not match
              NLog.w('return of targetId not match'+state.target.toString());
              return;
            }
          }

          /// handle update of entityMessage(send/receive)
          if (updateMessage.contentType == ContentType.text ||
              updateMessage.contentType == ContentType.textExtension ||
              updateMessage.contentType == ContentType.nknImage ||
              updateMessage.contentType == ContentType.media ||
              updateMessage.contentType == ContentType.nknAudio ||
              updateMessage.contentType == ContentType.eventSubscribe ||
              updateMessage.contentType == ContentType.eventContactOptions) {
            if (updateMessage.isSendMessage() == false){
              updateMessage.setMessageStatus(MessageStatus.MessageReceivedRead);
            }
            if (updateMessage.burnAfterSeconds != null) {
              updateMessage.deleteTime = DateTime.now().add(
                  Duration(seconds: updateMessage.burnAfterSeconds));
              updateMessage.updateDeleteTime();
            }
            setState(() {
              _messages.insert(0, updateModel);
              _messageBloc.add(UpdateMessageListEvent(targetId));
            });
          }
          /// handle update of receipt
          else if (updateMessage.contentType == ContentType.receipt){
            if (_messages != null && _messages.length > 0) {
              if (updateMessage.contentType == ContentType.receipt) {
                for (MessageModel model in _messages){
                  MessageSchema message = model.messageEntity;
                  if (message.msgId == updateMessage.content && message.isSendMessage()){
                    setState(() {
                      message.setMessageStatus(MessageStatus.MessageSendReceipt);
                      NLog.w('ReceivedMessageReceipt____'+message.content.toString());
                    });
                  }
                }
                return;
              }
            }
          }
          if (updateMessage.burnAfterSeconds != null) {
            /// not update other's setting
            if (updateMessage.from == targetId || updateMessage.from == NKNClientCaller.currentChatId){
              ContactSchema chatContact = updateModel.contactEntity;
              if (chatContact.options != null) {
                if (chatContact.options.updateBurnAfterTime == null ||
                    updateMessage.timestamp.millisecondsSinceEpoch >
                        chatContact.options.updateBurnAfterTime) {
                  chatContact.setBurnOptions(updateMessage.burnAfterSeconds);
                  setState(() {});
                }
              }
            }
          }
          if (updateMessage.contentType == ContentType.eventContactOptions){
            /// not update other's setting
            if (updateMessage.from == targetId || updateMessage.from == NKNClientCaller.currentChatId){
              Map<String,dynamic> eventContent = jsonDecode(updateMessage.content);
              if (eventContent['content'] != null && updateMessage.isSendMessage() == false) {
                var contentJson = eventContent['content'];
                var deleteAfterSeconds = contentJson['deleteAfterSeconds'].toString();
                if (contentJson['deleteAfterSeconds'] == null){
                  contactInfo.setBurnOptions(null);
                }
                else{
                  contactInfo.setBurnOptions(int.parse(deleteAfterSeconds.toString()));
                }
                setState(() {});
              }
            }
          }
        }
      });

      _scrollController.addListener(() {
        double offsetFromBottom = _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels;
        if (offsetFromBottom < 50 && !loading) {
          loading = true;
          _loadMore().then((v) {
            loading = false;
          });
        }
      });

      String content = LocalStorage.getChatUnSendContentFromId(
          NKNClientCaller.currentChatId, targetId) ??
          '';
      if (mounted)
        setState(() {
          _sendController.text = content;
          _canSend = content.length > 0;
        });
    });
  }

  _deleteTickHandle() {
    _deleteTick = Timer.periodic(Duration(seconds: 1), (timer) {
      for (MessageModel model in _messages){
        MessageSchema message = model.messageEntity;
        if (message.deleteTime != null){
          message.showBurnAfterSeconds = message.deleteTime.difference(DateTime.now()).inSeconds;
          if (message.showBurnAfterSeconds < 0){
            NLog.w('_deleteTickHandle delete BurnAfterReading Message'+message.content.toString());
            message.deleteMessage();
            initAsync();
          }
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    Global.currentOtherChatId = null;
    LocalStorage.saveChatUnSendContentWithId(
        NKNClientCaller.currentChatId, targetId,
        content: _sendController.text);
    _chatBloc.add(RefreshMessageListEvent(targetId: targetId));
    _chatSubscription?.cancel();
    _scrollController?.dispose();
    _sendController?.dispose();
    _sendFocusNode?.dispose();
    _deleteTick?.cancel();
    refreshSubscribersTimer?.cancel();
    super.dispose();
  }

  _sendMessageFormat(MessageSchema sendMsg) async{
    if (contactInfo?.options != null) {
      if (contactInfo?.options?.deleteAfterSeconds != null) {
        if (sendMsg.contentType == ContentType.text){
          sendMsg.contentType = ContentType.textExtension;
        }
        if (sendMsg.options == null){
          sendMsg.options = {};
        }
        sendMsg.options['deleteAfterSeconds'] = contactInfo.options.deleteAfterSeconds;
        sendMsg.burnAfterSeconds = contactInfo.options.deleteAfterSeconds;
      }
    }
    if (contactInfo != null){
      sendMsg.to = contactInfo.clientAddress;
    }
    if (topicInfo != null){
      sendMsg.topic = topicInfo.topic;
    }
  }

  _sendMessage(MessageSchema sendMsg) async{
    try {
      MessageModel model = await MessageModel.modelFromMessageFrom(sendMsg);
      setState(() {
        _messages.insert(0, model);
      });
      _chatBloc.add(SendMessageEvent(sendMsg));
    } catch (e) {
      if (e != null) {
        NLog.w('_sendMessage E' + e.toString());
      }
    }
  }

  _sendTestMessage() async {
    int contentIndex = 1;
    Timer _testMessageTimer;

    String sendTestString = DateTime.now().day.toString() +
        '日' +
        DateTime.now().hour.toString() +
        '时' +
        DateTime.now().minute.toString() +
        '分';
    _testMessageTimer = Timer.periodic(Duration(milliseconds: 10), (timer) {
      String dest = targetId;

      String contentType = ContentType.text;
      String content =
          'QeqNYLoTghIQMBAiPNMJxNhshogb+qCNJDhebIELnzXIONky2J0pmc29kE8pMoESSck9UiSDAx3VXUBsi4goL0WLhiVIsDsmCQ7S47bHKRB1QI9EAZJDpIBymR5YEHsiCIEWR8pgiBFpQAEyDhBAAgEBMmBfGbKcGTaee6AaZic/ZXA0wLyoN3Qm2Rk27IKIgHmk2AJuOXVJ7hGUjdkfiFkDgEGW3CIcLkyMSEgAWxBComwm5QAbAgBM87TG15UgjJgJNBG1kFGDzvmEQBYQI3CDi1rpTJIj1KBNnVsbxCpw5m3JONPIpDEhA5jcxupIBH2Q4kTMgd0gYMxndA48wvfmqNh07KSQM2hVaTMHoggWTbPO/M7ptbM23QLHERhABsi5N0T5yMyl5g6RcbCJlOzrxPYIFcc77IcJCBm4Ko2EFApgY1IIM2G8dU4seaNUtzG3ZAOvBGxQL3Gd4wk7NpmENMG6B6p3Q0eWd+iJtMme6U+WTidigMHmnB/ooEEdrJGZIBt0QFsafRGTv3RJmJQSS0NvbqgR8v4jJygibkek4T1QOSQIgOBMHmgMgEG6fzG+QkBeYQfmkCPogV7ggeyYMHa+QUcrFMgEyJzlAC9jYoJBvuU87pFsGUCERc3TJm4vZKby76p5IDYsUC3gyCeSBZ0nsqAAFxnnulECdQjqgekRq5HZTOMeqATvztdPN+l4QABJvYI0wbHKG90SgLz02VDS6ZxsYwl1Ewn6IEYlw3G6C05It0RY4EfomXWxI7oADkm44O+FMmMEz1SAMzM/ogcCcBB6EgjYboLouSkec9oQAnYXQZPRPrKLeqBAQZBujbCBY2zvCDAiUDygnmgHyiUi0EYQMXtsg2KaUkm3ugPe6cQRGeaO1kIMoHy789lWCERe5iUHNkDBvhBsMeygu5J6Tk7oG2CJTiJIsTzSkz6JkgmOiBEkWaJKQbubuj2TEiAg90CGLjCcnMJ5yEiWnyoCZMY3wlBD5CrrEJOHIWyEARBuUhMhNpDhcKgY5+iCXEGLEIGZhBgi155Kc33GZQaGdMqSbxFt0AgwZ+qTvOcWQVBxMckNnefRGRAQIjr1QKZ7eyJm4MoIOkkAGED5RE/ZASAOSNzyKV7JwCL2CADDMki32TGZJxYJQQ7IiNzdORbN0CJIFp7pCS9zcEXlGq/lF07NHmNycIEDM6XXbugA7xjmgHsEybg+iADb7lAI6d0snVqg7pztsgl4IE3AVN0gjzWOEyBAkkKIDTf7wgtwi4Mg4ISDZHmAneENZOBBVRBMjvBQIXBHvZHltghPJF+cIExIA90CwbzHRFgM/uiJ5iMIDrxcGbIE4kgBMYAkd+aLzzQRIjZAtiIsbg==';
      content =
          'TestMessage' + sendTestString + '\n(_test_)' + contentIndex.toString();
      // content = content+content;
      // content = content+content;
      // content = content+content;
      contentIndex++;
      if (contentIndex == 501) {
        _testMessageTimer.cancel();
      }

      NLog.w('Test_send_message_length__' + content.length.toString());

      MessageSchema sendMsg = MessageSchema.formSendMessage(
        from: NKNClientCaller.currentChatId,
        content: content,
        contentType: ContentType.text,
      );
      _sendMessageFormat(sendMsg);
      _sendMessage(sendMsg);
    });
  }

  _sendText() async {
    LocalStorage.saveChatUnSendContentWithId(
        NKNClientCaller.currentChatId, targetId);
    String text = _sendController.text;
    if (text == null || text.length == 0) return;
    _sendController.clear();
    _canSend = false;

    if (text == '测试消息'){
      _sendTestMessage();
      return;
    }

    MessageSchema sendMsg = MessageSchema.formSendMessage(
        from: NKNClientCaller.currentChatId,
        content: text,
        contentType: ContentType.text,
    );
    _sendMessageFormat(sendMsg);
    _sendMessage(sendMsg);
  }

  _sendAudio(File audioFile, double audioDuration) async {
    var sendMsg = MessageSchema.formSendMessage(
      from: NKNClientCaller.currentChatId,
      content: audioFile,
      contentType: ContentType.nknAudio,
      audioFileDuration: audioDuration,
    );
    _sendMessageFormat(sendMsg);
    _sendMessage(sendMsg);
  }

  _sendImage(File savedImg) async {
    var sendMsg = MessageSchema.formSendMessage(
      from: NKNClientCaller.currentChatId,
      content: savedImg,
      contentType: ContentType.media,
    );
    _sendMessageFormat(sendMsg);
    _sendMessage(sendMsg);
  }

  getImageFile({@required ImageSource source}) async {
    try {
      File image =
      await getCameraFile(NKNClientCaller.currentChatId, source: source);
      if (image != null) {
        _sendImage(image);
      }
    } catch (e) {
      debugPrintStack();
      debugPrint(e);
    }
  }

  _toggleBottomMenu() async {
    setState(() {
      _showBottomMenu = !_showBottomMenu;
    });
  }

  _hideAll() {
    FocusScope.of(context).requestFocus(FocusNode());
    setState(() {
      _showBottomMenu = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget topWidegt;
    if (topicInfo == null){
      topWidegt = _singleChatTopWidget();
    }
    else{
      topWidegt = _topicChatTopWidget();
    }

    return Scaffold(
      backgroundColor: DefaultTheme.backgroundColor4,
      appBar: topWidegt,
      body: GestureDetector(
        onTap: () {
          _hideAll();
        },
        child: BodyBox(
          padding: const EdgeInsets.only(top: 0),
          color: DefaultTheme.backgroundLightColor,
          child: Container(
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding:
                      const EdgeInsets.only(left: 12, right: 16, top: 4),
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.only(bottom: 8),
                        controller: _scrollController,
                        itemCount: _messages.length,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (BuildContext context, int index) {
                          MessageModel currentMessageModel = _messages[index];
                          MessageSchema currentMessage = _messages[index].messageEntity;

                          bool showTime;
                          bool hideHeader = false;
                          if (index + 1 >= _messages.length) {
                            showTime = true;
                          } else {
                            MessageModel messageModel;
                            if (index == _messages.length){
                              messageModel = currentMessageModel;
                            }
                            else{
                              messageModel = _messages[index+1];
                            }
                            var preMessage = messageModel.messageEntity;
                            if (preMessage.contentType == ContentType.text ||
                                preMessage.contentType ==
                                    ContentType.nknImage ||
                                preMessage.contentType == ContentType.media ||
                                preMessage.contentType ==
                                    ContentType.nknAudio) {
                              showTime = (currentMessage.timestamp.isAfter(preMessage
                                  .timestamp
                                  .add(Duration(minutes: 3))));
                            } else {
                              showTime = true;
                            }
                          }

                          if (topicInfo != null){
                            if (currentMessage.contentType == ContentType.eventSubscribe){
                              String fromUid = NL10ns.of(context).you+NL10ns.of(context).joined_channel;
                              if (currentMessage.isSendMessage() == false){
                                if (currentMessage.from != null && currentMessage.from.length > 6){
                                  fromUid = currentMessage.from.substring(0,6)+NL10ns.of(context).joined_channel;
                                }
                              }
                              return ChatSystem(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Label(
                                        '$fromUid'),
                                  ],
                                ),
                              );
                            }
                            else if (currentMessage.contentType == ContentType.eventUnsubscribe) {
                              return Container();
                            }
                          }
                          else{
                            if (currentMessage.contentType == ContentType.eventContactOptions){
                              return _contactOptionWidget(index);
                            }
                          }
                          return ChatBubble(
                            message: currentMessageModel,
                            showTime: showTime,
                            hideHeader: hideHeader,
                            onChanged: (String v){
                              setState(() {
                                _sendController.text =
                                    _sendController.text + ' @$v ';
                                _canSend = true;
                              });
                            },
                            resendMessage: (String msgId){
                              /// resendMessage Logic
                              _resendMessage(msgId);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  _audioInputWidget(),
                  _bottomMenuWidget(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _resendMessage(String msgId) async{
    NLog.w('Resend msgId is______'+msgId.toString());
    SimpleConfirm(
        context: context,
        content: 'Resend Message?',
        buttonText: NL10ns
            .of(context)
            .ok,
        buttonColor: Colors.red,
        callback: (v) async{
          if (v) {
            MessageSchema resendMsg = await MessageDataCenter.resendMessage(msgId);

            resendMsg.messageStatus = MessageStatus.MessageSending;
            MessageModel model = await MessageModel.modelFromMessageFrom(resendMsg);
            setState(() {
              for (int i = 0; i < _messages.length; i++){
                MessageModel checkMsg = _messages[i];
                if (checkMsg.messageEntity.msgId == msgId){
                  _messages.removeAt(i);
                  _messages.insert(i, model);
                  break;
                }
              }
            });
            _chatBloc.add(SendMessageEvent(resendMsg));
          }
        }).show();
  }

  _pushToContactSettingPage() async{
    contactInfo = await ContactSchema.fetchContactByAddress(
        contactInfo.clientAddress);
    Navigator.of(context)
        .pushNamed(ContactScreen.routeName, arguments: contactInfo)
        .then((v) async {
      Duration duration = Duration(milliseconds: 10);
      if (v == null){
        duration = Duration(milliseconds: 350);
      }
      Timer(duration, () async{
        _chatBloc.add(RefreshMessageListEvent(targetId: targetId));
        setState(() {
          _acceptNotification = false;
          if (contactInfo.notificationOpen != null) {
            _acceptNotification = contactInfo.notificationOpen;
          }
        });
      });
    });
  }

  Widget _topicChatTopWidget(){
    List<Widget>  topicWidget = [
      Label(topicInfo.topicShort, type: LabelType.h3, dark: true)
    ];
    if (topicInfo.isPrivateTopic()) {
      topicWidget.insert(
          0,
          loadAssetIconsImage('lock',
              width: 18, color: DefaultTheme.fontLightColor)
              .pad(r: 2));
    }
    return Header(
      titleChild: GestureDetector(
        onTap: () async {
          Navigator.of(context)
              .pushNamed(ChannelSettingsScreen.routeName,
              arguments: topicInfo)
              .then((v) {
            if (v == true) {
              Navigator.of(context).pop(true);
              EasyLoading.dismiss();
            }
          });
        },
        child: Flex(
            direction: Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 0,
                child: Container(
                  padding: EdgeInsets.only(right: 10.w),
                  alignment: Alignment.center,
                  child: Hero(
                    tag: 'avatar:${targetId}',
                    child: Container(
                      child: CommonUI.avatarWidget(
                        radiusSize: 24,
                        topic: topicInfo,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: topicWidget),
                    BlocBuilder<ChannelBloc, ChannelState>(
                        builder: (context, state) {
                          if (state is ChannelMembersState) {
                            if (state.memberCount != null && state.topicName == targetId) {
                              _topicCount = state.memberCount;
                            }
                          }
                          return Label(
                            '${(_topicCount == null || _topicCount < 0) ? '--' : _topicCount} ' +
                                NL10ns.of(context).members,
                            type: LabelType.bodySmall,
                            color: DefaultTheme.riseColor,
                          ).pad(
                              l: topicInfo.isPrivateTopic()
                                  ? 20
                                  : 0);
                        })
                  ],
                ),
              )
            ]),
      ),
      backgroundColor: DefaultTheme.backgroundColor4,
      action: FlatButton(
        onPressed: () {
          Navigator.of(context).pushNamed(ChannelMembersScreen.routeName,
              arguments: topicInfo);
        },
        child: loadAssetChatPng('group', width: 22),
      ).sized(w: 72),
    );
  }

  Widget _singleChatTopWidget(){
    notiBellColor = DefaultTheme.primaryColor;
    if (_acceptNotification == false) {
      notiBellColor = Colors.white38;
    }
    return Header(
        titleChild: GestureDetector(
          onTap: ()=> {
            _pushToContactSettingPage()
          },
          child: Flex(
            direction: Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 0,
                child: Container(
                  padding: EdgeInsets.only(right: 14.w),
                  alignment: Alignment.center,
                  child: Container(
                    child: CommonUI.avatarWidget(
                      radiusSize: 24,
                      contact: contactInfo,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Label(contactInfo.getShowName,
                        type: LabelType.h3, dark: true),
                    getBurnTimeView()
                  ],
                ),
              ),
              FlatButton(
                child: loadAssetIconsImage('notification_bell',
                    color: notiBellColor, width: 24),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _acceptNotification = !_acceptNotification;
                      _saveAndSendDeviceToken();
                    });
                  }
                },
              ),
            ],
          ),
        ),
        backgroundColor: DefaultTheme.backgroundColor4,
        action: Container(
          margin: EdgeInsets.only(left: 8, right: 8),
          child: GestureDetector(
            child: loadAssetIconsImage('more', width: 24),
            onTap: () => {
              _pushToContactSettingPage(),
            },
          ),
        ));
  }

  _saveAndSendDeviceToken() async {
    String deviceToken = '';
    deviceToken = await NKNClientCaller.fetchDeviceToken();
    contactInfo.notificationOpen = _acceptNotification;
    if (_acceptNotification == true) {
      if (Platform.isIOS) {
        String fcmToken = await NKNClientCaller.fetchFcmToken();
        if (fcmToken != null && fcmToken.length > 0) {
          deviceToken = deviceToken + "$fcmGapString$fcmToken";
        }
      }
      if (Platform.isAndroid && deviceToken.length == 0) {
        showToast(NL10ns.of(context).unavailable_device);
        setState(() {
          _acceptNotification = false;
          contactInfo.notificationOpen = false;
          contactInfo.setNotificationOpen(_acceptNotification);
        });
        return;
      }
    } else {
      deviceToken = '';
      showToast(NL10ns.of(context).close);
    }
    await contactInfo.setNotificationOpen(_acceptNotification);
    _chatBloc.add(RefreshMessageListEvent(targetId: targetId));

    var sendMsg = MessageSchema.formSendMessage(
      from: NKNClientCaller.currentChatId,
      to: contactInfo.clientAddress,
      contentType: ContentType.eventContactOptions,
      deviceToken: deviceToken,
    );
    sendMsg.deviceToken = deviceToken;
    sendMsg.content = sendMsg.toContactNoticeOptionData();

    _addMessageToList(sendMsg);
  }

  _addMessageToList(MessageSchema sendMsg) async {
    if (mounted) {
      MessageModel model = await MessageModel.modelFromMessageFrom(sendMsg);
      setState(() {
        _messages.insert(0, model);
      });
    }
    _chatBloc.add(SendMessageEvent(sendMsg));

    String savedKey =
        LocalStorage.NKN_MESSAGE_NOTIFICATION_ALERT + ':' + targetId.toString();

    /// No Alert of Notification2Open before
    print('LocalKey is___' + savedKey);

    if (_messages.length > 0) {
      String isNotificationOpenAlert = await LocalStorage().get(savedKey);
      if (isNotificationOpenAlert == null && _acceptNotification == false) {
        _judgeIfAlertOpenNotification();
      }
    }
  }

  _judgeIfAlertOpenNotification() {
    int sendCount = 0;
    int receiveCount = 0;
    for (MessageModel message in _messages) {
      if (message.messageEntity.isSendMessage()) {
        sendCount++;
      } else {
        receiveCount++;
      }
    }

    if (sendCount >= 3 && receiveCount >= 3) {
      SimpleConfirm(
        context: context,
        buttonColor: DefaultTheme.primaryColor,
        content:
        NL10ns.of(context).tip_open_send_device_token,
        callback: (b) {
          if (b) {
            _acceptNotification = true;
            _saveAndSendDeviceToken();
          }
          String savedKey = LocalStorage.NKN_MESSAGE_NOTIFICATION_ALERT +
              ':' +
              targetId.toString();
          LocalStorage().set(savedKey, 'YES');
        },
        buttonText: NL10ns.of(context).ok,
      ).show();
    }
  }

  Widget _contactOptionWidget(int index) {
    MessageModel messageModel = _messages[index];
    MessageSchema message = messageModel.messageEntity;
    ContactSchema showContact = messageModel.contactEntity;
    Map optionData = jsonDecode(message.content);
    if (optionData['content'] != null) {
      var deleteAfterSeconds = optionData['content']['deleteAfterSeconds'];
      if (deleteAfterSeconds != null && deleteAfterSeconds > 0) {
        return ChatSystem(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_on,
                          size: 16, color: DefaultTheme.fontColor2)
                          .pad(b: 1, r: 4),
                      Label(
                          Format.durationFormat(Duration(
                              seconds: optionData['content']
                              ['deleteAfterSeconds'])),
                          type: LabelType.bodySmall),
                    ],
                  ).pad(b: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Label(
                        message.isSendMessage()
                            ? NL10ns.of(context).you
                            : showContact.getShowName,
                        fontWeight: FontWeight.bold,
                      ),
                      Label(' ${NL10ns.of(context).update_burn_after_reading}',
                          softWrap: true),
                    ],
                  ).pad(b: 4),
                  InkWell(
                    child: Label(NL10ns.of(context).click_to_change,
                        color: DefaultTheme.primaryColor,
                        type: LabelType.bodyRegular),
                    onTap: () {
                      _pushToContactSettingPage();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      } else if (optionData['content']['deviceToken'] != null) {
        String deviceToken = optionData['content']['deviceToken'];

        String deviceDesc = "";
        if (deviceToken.length == 0) {
          deviceDesc = ' ${NL10ns.of(context).setting_deny_notification}';
        } else {
          deviceDesc = ' ${NL10ns.of(context).setting_accept_notification}';
        }
        return ChatSystem(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Label(
                        message.isSendMessage()
                            ? NL10ns.of(context).you
                            : showContact.getShowName,
                        fontWeight: FontWeight.bold,
                      ),
                      Label('$deviceDesc'),
                    ],
                  ).pad(b: 4),
                  InkWell(
                    child: Label(NL10ns.of(context).click_to_change,
                        color: DefaultTheme.primaryColor,
                        type: LabelType.bodyRegular),
                    onTap: () {
                      _pushToContactSettingPage();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      } else {
        return ChatSystem(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_off,
                          size: 16, color: DefaultTheme.fontColor2)
                          .pad(b: 1, r: 4),
                      Label(NL10ns.of(context).off,
                          type: LabelType.bodySmall,
                          fontWeight: FontWeight.bold),
                    ],
                  ).pad(b: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Label(
                        message.isSendMessage()
                            ? NL10ns.of(context).you
                            : showContact.getShowName,
                        fontWeight: FontWeight.bold,
                      ),
                      Label(' ${NL10ns.of(context).close_burn_after_reading}'),
                    ],
                  ).pad(b: 4),
                  InkWell(
                    child: Label(NL10ns.of(context).click_to_change,
                        color: DefaultTheme.primaryColor,
                        type: LabelType.bodyRegular),
                    onTap: () {
                      _pushToContactSettingPage();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      }
    } else {
      return Container();
    }
  }

  getBurnTimeView() {
    if (contactInfo?.options != null &&
        contactInfo?.options?.deleteAfterSeconds != null) {
      return Row(
        children: [
          Icon(Icons.alarm_on,
              size: 16, color: DefaultTheme.backgroundLightColor)
              .pad(r: 4),
          Label(
            Format.durationFormat(
                Duration(seconds: contactInfo?.options?.deleteAfterSeconds)),
            type: LabelType.bodySmall,
            color: DefaultTheme.backgroundLightColor,
          ),
        ],
      ).pad(t: 2);
    } else {
      return Label(
        NL10ns.of(context).click_to_settings,
        type: LabelType.bodySmall,
        color: DefaultTheme.backgroundLightColor,
      );
    }
  }

  Widget _menuWidget() {
    double audioHeight = 65;
    if (_showAudioInput == true) {
      if (_recordAudio == null) {
        _recordAudio = RecordAudio(
          height: audioHeight,
          margin: EdgeInsets.only(top: 15, bottom: 15, right: 0),
          startRecord: startRecord,
          stopRecord: stopRecord,
          cancelRecord: _cancelRecord,
        );
      }
      return Container(
        height: audioHeight,
        margin: EdgeInsets.only(top: 15, right: 0),
        child: _recordAudio,
      );
    }
    return Container(
      constraints: BoxConstraints(minHeight: 70, maxHeight: 160),
      child: Flex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            flex: 0,
            child: Container(
              margin:
              const EdgeInsets.only(left: 0, right: 0, top: 15, bottom: 15),
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: ButtonIcon(
                width: 50,
                height: 50,
                icon: loadAssetIconsImage(
                  'grid',
                  width: 24,
                  color: DefaultTheme.primaryColor,
                ),
                onPressed: () {
                  _toggleBottomMenu();
                },
              ),
            ),
          ),
          _sendWidget(),
          _voiceAndSendWidget(),
        ],
      ),
    );
  }

  Widget _voiceAndSendWidget() {
    if (_canSend) {
      return Expanded(
        flex: 0,
        child: Container(
          margin: EdgeInsets.only(top: 15, bottom: 15),
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: ButtonIcon(
            width: 50,
            height: 50,
            icon: loadAssetIconsImage(
              'send',
              width: 24,
              color: DefaultTheme.primaryColor,
            ),
            onPressed: () {
              _sendText();
            },
          ),
        ),
      );
    }
    return Expanded(
      flex: 0,
      child: Container(
        margin: EdgeInsets.only(top: 15, bottom: 15),
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: _voiceWidget(),
      ),
    );
  }

  Widget _voiceWidget() {
    return Container(
      width: 50,
      height: 50,
      margin: EdgeInsets.only(right: 0),
      child: ButtonIcon(
        width: 50,
        height: 50,
        icon: loadAssetIconsImage(
          'microphone',
          color: DefaultTheme.primaryColor,
          width: 24,
        ),
        onPressed: () {
          _voiceAction();
        },
      ),
    );
  }

  Widget _bottomMenuWidget() {
    return Expanded(
        flex: 0,
        child: ExpansionLayout(
          isExpanded: _showBottomMenu,
          child: Container(
            padding:
            const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: DefaultTheme.backgroundColor2),
              ),
            ),
            child: _pictureWidget(),
          ),
        ));
  }

  Widget _sendWidget() {
    return Expanded(
      flex: 1,
      child: Container(
        margin: const EdgeInsets.only(left: 0, right: 0, top: 15, bottom: 15),
        decoration: BoxDecoration(
          color: DefaultTheme.backgroundColor1,
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Flex(
          direction: Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              flex: 1,
              child: TextField(
                maxLines: 5,
                minLines: 1,
                controller: _sendController,
                focusNode: _sendFocusNode,
                textInputAction: TextInputAction.newline,
                onChanged: (val) {
                  if (mounted) {
                    setState(() {
                      _canSend = val.isNotEmpty;
                    });
                  }
                },
                style: TextStyle(fontSize: 14, height: 1.4),
                decoration: InputDecoration(
                  hintText: NL10ns.of(context).type_a_message,
                  contentPadding:
                  EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
                  border: UnderlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20.w)),
                    borderSide:
                    const BorderSide(width: 0, style: BorderStyle.none),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioInputWidget(){
    if (showJoin == false){
      return Container(
        margin: EdgeInsets.only(left: 5,right: 5),
        child: Button(
          child:Label(
            NL10ns.of(context).tip_ask_group_owner_permission,
            type: LabelType.h4,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: DefaultTheme.primaryColor,
          width: double.infinity,
        ).pad(l: 20, r: 20),
      );
    }
    double wWidth = MediaQuery.of(context).size.width;
    return Container(
      height: 90,
      margin: EdgeInsets.only(bottom: 0),
      child: GestureDetector(
        child: _menuWidget(),
        onTapUp: (details) {
          int afterSeconds =
              DateTime.now().difference(cTime).inSeconds;
          setState(() {
            _showAudioLock = false;
            if (afterSeconds > 1) {
              /// send AudioMessage Here
              NLog.w('Audio record less than 1s' +
                  afterSeconds.toString());
            } else {
              /// add viberation Here
              _showAudioInput = false;
            }
          });
        },
        onLongPressStart: (details) {
          cTime = DateTime.now();
          _showAudioLock = false;
          Vibration.vibrate();
          _setAudioInputOn(true);
        },
        onLongPressEnd: (details) {
          int afterSeconds =
              DateTime.now().difference(cTime).inSeconds;
          setState(() {
            if (details.globalPosition.dx < (wWidth - 80)){
              if (_recordAudio != null) {
                _recordAudio.cancelCurrentRecord();
                _recordAudio.cOpacity = 1;
              }
            }
            else{
              if (_recordAudio.showLongPressState == false) {

              } else {
                _recordAudio.stopAndSendAudioMessage();
              }
            }
            if (afterSeconds > 0.2 &&
                _recordAudio.cOpacity > 0) {
            } else {
              _showAudioInput = false;
            }
            if (_showAudioLock) {
              _showAudioLock = false;
            }
          });
        },
        onLongPressMoveUpdate: (details) {
          int afterSeconds =
              DateTime.now().difference(cTime).inSeconds;
          if (afterSeconds > 0.2) {
            setState(() {
              _showAudioLock = true;
            });
          }
          if (details.globalPosition.dx >
              (wWidth) / 3 * 2 &&
              details.globalPosition.dx < wWidth - 80) {
            double cX = details.globalPosition.dx;
            double tW = wWidth - 80;
            double mL = (wWidth) / 3 * 2;
            double tL = tW - mL;
            double opacity = (cX - mL) / tL;
            if (opacity < 0) {
              opacity = 0;
            }
            if (opacity > 1) {
              opacity = 1;
            }

            setState(() {
              _recordAudio.cOpacity = opacity;
            });
          } else if (details.globalPosition.dx > wWidth - 80) {
            setState(() {
              _recordAudio.cOpacity = 1;
            });
          }
          double gapHeight = 90;
          double tL = 50;
          double mL = 60;
          if (details.globalPosition.dy >
              MediaQuery.of(context).size.height -
                  (gapHeight + tL) &&
              details.globalPosition.dy <
                  MediaQuery.of(context).size.height -
                      gapHeight) {
            setState(() {
              double currentL = (tL -
                  (MediaQuery.of(context).size.height -
                      details.globalPosition.dy -
                      gapHeight));
              _audioLockHeight = mL + currentL - 10;
              if (_audioLockHeight < mL) {
                _audioLockHeight = mL;
              }
            });
          }
          if (details.globalPosition.dy <
              MediaQuery.of(context).size.height -
                  (gapHeight + tL)) {
            setState(() {
              _audioLockHeight = mL;
              _recordAudio.showLongPressState = false;
              _audioLongPressEndStatus = true;
            });
          }
          if (details.globalPosition.dy >
              MediaQuery.of(context).size.height -
                  (gapHeight)) {
            _audioLockHeight = 90;
          }
        },
        onHorizontalDragEnd: (details) {
          _cancelAudioRecord();
        },
        onHorizontalDragCancel: () {
          _cancelAudioRecord();
        },
        onVerticalDragCancel: () {
          _cancelAudioRecord();
        },
        onVerticalDragEnd: (details) {
          _cancelAudioRecord();
        },
      ),
    );
  }

  _cancelAudioRecord() {
    if (_audioLongPressEndStatus == false) {
      if (_recordAudio != null) {
        _recordAudio.cancelCurrentRecord();
      }
    }
    setState(() {
      _showAudioLock = false;
    });
  }

  _setAudioInputOn(bool audioInputOn) {
    setState(() {
      if (audioInputOn) {
        _showAudioInput = true;
      } else {
        _showAudioInput = false;
      }
    });
  }

  _voiceAction() {
    _setAudioInputOn(true);
    Vibration.vibrate();
    Timer(Duration(milliseconds: 350), () async {
      _setAudioInputOn(false);
    });
  }

  _cancelRecord() {
    _setAudioInputOn(false);
    Vibration.vibrate();
  }

  startRecord() {
    NLog.w('startRecord called');
  }

  stopRecord(String path, double audioTimeLength) async {
    NLog.w('stopRecord called');
    _setAudioInputOn(false);

    File audioFile = File(path);
    if (!audioFile.existsSync()) {
      audioFile.createSync();
      audioFile = File(path);
    }
    int fileLength = await audioFile.length();

    if (fileLength != null && audioTimeLength != null) {
      NLog.w('Record finished with fileLength__' +
          fileLength.toString() +
          'audioTimeLength is__' +
          audioTimeLength.toString());
    }
    if (fileLength == 0) {
      showToast('Record file wrong.Please record again.');
      return;
    }
    if (audioTimeLength > 1.0) {
      _sendAudio(audioFile, audioTimeLength);
    }
  }

  Widget _pictureWidget() {
    return Flex(
      direction: Axis.horizontal,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          flex: 0,
          child: Column(
            children: <Widget>[
              SizedBox(
                width: 71,
                height: 71,
                child: FlatButton(
                  color: DefaultTheme.backgroundColor1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8))),
                  child: loadAssetIconsImage(
                    'image',
                    width: 32,
                    color: DefaultTheme.fontColor2,
                  ),
                  onPressed: () {
                    getImageFile(source: ImageSource.gallery);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Label(
                  NL10ns.of(context).pictures,
                  type: LabelType.bodySmall,
                  color: DefaultTheme.fontColor2,
                ),
              )
            ],
          ),
        ),
        Expanded(
          flex: 0,
          child: Column(
            children: <Widget>[
              SizedBox(
                width: 71,
                height: 71,
                child: FlatButton(
                  color: DefaultTheme.backgroundColor1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8))),
                  child: loadAssetIconsImage(
                    'camera',
                    width: 32,
                    color: DefaultTheme.fontColor2,
                  ),
                  onPressed: () {
                    getImageFile(source: ImageSource.camera);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Label(
                  NL10ns.of(context).camera,
                  type: LabelType.bodySmall,
                  color: DefaultTheme.fontColor2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
