

import 'dart:async';
import 'dart:convert';

import 'package:nmobile/blocs/nkn_client_caller.dart';
import 'package:nmobile/helpers/hash.dart';
import 'package:nmobile/helpers/local_storage.dart';
import 'package:nmobile/model/db/nkn_data_manager.dart';
import 'package:nmobile/model/entity/subscriber_repo.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/model/group_chat_helper.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:oktoast/oktoast.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class GroupDataCenter{
  static String subscriberTableName = 'subscriber';

  static SubscriberRepo subRepo = SubscriberRepo();
  static TopicRepo topicRepo = TopicRepo();

  Future<int> getCountOfTopic(topicName,int memberStatus) async {
    Database cdb = await NKNDataManager().currentDatabase();
    var res = await cdb.query(
        subscriberTableName,
        where: 'topic = ? AND member_status = ?',
        whereArgs:[topicName, memberStatus],
    );
    if (res != null){
      return res.length;
    }
    return 0;
  }

  static Future<List<Subscriber>> fetchSubscribedMember(String topicName) async{
    List<Subscriber> memberList = await subRepo.getAllMemberByTopic(topicName);
    return memberList;
  }

  static Future<List<String>> fetchGroupMembersTargets(String topicName) async {
    List<Subscriber> memberList = await subRepo.getAllMemberByTopic(topicName);

    List<String> resultList = new List<String>();
    if (memberList.isNotEmpty){
      for (Subscriber sub in memberList){
        resultList.add(sub.chatId);
      }
    }
    if (resultList.length > 0){
      return resultList;
    }
    return null;
  }

  static Future<List<Subscriber>> fetchLocalGroupMembers(String topicName) async{
    Database cdb = await NKNDataManager().currentDatabase();
    List<Map<String, dynamic>> result = await cdb.query(subscriberTableName,
        where: 'topic = ?',
        whereArgs: [topicName],
        orderBy: 'time_create ASC');

    List<Subscriber> groupMembers = List<Subscriber>();
    if (result != null && result.length > 0){
      for (Map subscriber in result){
        NLog.w('Subscriber is____'+subscriber.toString());
      }
      Subscriber sub = Subscriber(

      );
      groupMembers.add(sub);
    }
    return groupMembers;
  }

  static Future<bool> updatePrivatePermissionList(String topicName,String chatId, bool invite) async{
    Subscriber updateSub = await subRepo.getByTopicAndChatId(topicName, chatId);
    final topicHashed = genTopicHash(topicName);

    if (updateSub == null){
      NLog.w('Wrong!!!__updateSub is null');
    }

    bool updateResult;
    if (invite){
      NLog.w('UpdateStatus to MemberInvited');
      updateResult = await subRepo.updateMemberStatus(updateSub, MemberStatus.MemberInvited);
    }
    else{
      NLog.w('UpdateStatus to MemberPublishRejected');
      updateResult = await subRepo.updateMemberStatus(updateSub, MemberStatus.MemberPublishRejected);
    }

    String pubKey = NKNClientCaller.currentChatId;
    int pageIndex = 0;
    if (updateSub.indexPermiPage != null && updateSub.indexPermiPage != -1){
      pageIndex = updateSub.indexPermiPage;
    }

    List<Subscriber> pageMembers = await subRepo.findAllSubscribersWithPermitIndex(topicName, pageIndex);
    NLog.w('Subs pageIndex is_____'+pageIndex.toString());
    if (pageMembers != null && pageMembers.length > 0){
      List acceptList = new List();
      List rejectList = new List();
      Map cMap = new Map();
      for (int i = 0; i < pageMembers.length; i++){
        Subscriber subscriber = pageMembers[i];
        NLog.w('Subs chatId is_____'+subscriber.chatId.toString());
        Map memberInfo = new Map();
        memberInfo['addr'] = subscriber.chatId;
        if (subscriber.memberStatus == MemberStatus.MemberInvited ||
            subscriber.memberStatus == MemberStatus.MemberPublished ||
            subscriber.memberStatus == MemberStatus.MemberSubscribed){
          acceptList.add(memberInfo);
        }
        else{
          rejectList.add(memberInfo);
          /// todo check if out of judge
          // static const int DefaultNotMember = 0;
          // static const int MemberInvited = 1;
          // static const int MemberPublished = 2;
          // static const int MemberSubscribed = 3;
          // static const int MemberPublishRejected = 4;
          // static const int MemberJoinedButNotInvited = 5;
        }
      }
      cMap['accept'] = acceptList;
      cMap['reject'] = rejectList;
      String cMapString = jsonEncode(cMap);
      NLog.w('cMapString is________'+cMapString);

      /// save last subscribe time. If operated, operated 20s later.
      String appendMetaIndex = '__${pageIndex}__.__permission__';

      int responseTime = await LocalStorage().get(LocalStorage.NKN_SUBSRIBE_GAP_TIME);
      if (responseTime != null){
        DateTime responseTimeExpire =
        DateTime.fromMillisecondsSinceEpoch(responseTime);
        DateTime beforeTime = DateTime.now().subtract(Duration(seconds: 20));
        if (responseTimeExpire.isBefore(beforeTime)){
          NLog.w('responseTimeExpire is > =___'+responseTimeExpire.second.toString());
          // updatePrivateGroupMemberSubscribe(topicHashed, appendMetaIndex, cMapString);

          updatePrivateGroupMemberSubscribe(topicHashed, appendMetaIndex, cMapString);
          int responseTimeValue = DateTime.now().millisecondsSinceEpoch;
          await LocalStorage().set(LocalStorage.NKN_SUBSRIBE_GAP_TIME, responseTimeValue);
        }
        else{
          showToast('Operate too often,20s later!');
          /// todo should Do in Operation List
        }
        int responseTimeValue = DateTime.now().millisecondsSinceEpoch;
        await LocalStorage().set(LocalStorage.NKN_SUBSRIBE_GAP_TIME, responseTimeValue);
      }
      else{
        updatePrivateGroupMemberSubscribe(topicHashed, appendMetaIndex, cMapString);
        int responseTimeValue = DateTime.now().millisecondsSinceEpoch;
        await LocalStorage().set(LocalStorage.NKN_SUBSRIBE_GAP_TIME, responseTimeValue);
      }
    }
    else{
      NLog.w('Wrong!!! no pageMembers');
      ///Submit One member
    }
    return true;
    /// node sync job
  }

  static updatePrivateGroupMemberSubscribe(String topicHash, String appendMetaIndex, String cMapString) async{
    double minerFee = 0;
    try {
      await NKNClientCaller.subscribe(
        identifier: appendMetaIndex,
        topicHash: topicHash,
        duration: 400000,
        fee: minerFee.toString(),
        meta: cMapString,
      );
    } catch (e) {
      NLog.e('uploadPermissionMeta' + e.toString());
    }
  }

  static Future<int> addPrivatePermissionList(String topicName,String chatId) async{
    Subscriber sub = await subRepo.getByTopicAndChatId(topicName, chatId);
    if (sub == null){
      NLog.w('addPrivatePermissionList___'+chatId.toString());
      Subscriber insertSub = Subscriber(
          id: 0,
          topic: topicName,
          chatId: chatId,
          timeCreate: DateTime.now().millisecondsSinceEpoch,
          memberStatus: MemberStatus.MemberInvited);
      subRepo.insertSubscriber(insertSub);

      appendOneMemberOnChain(insertSub);
      /// Insert Logic
      return MemberStatus.MemberInvited;
    }
    return sub.memberStatus;
  }

  static Future<void> appendOneMemberOnChain(Subscriber sub) async{
    String topicName = sub.topic;
    final topicHashed = genTopicHash(topicName);
    int maxPageIndex = await subRepo.findMaxPermitIndex(sub.topic);
    NLog.w('maxPageIndex is____'+maxPageIndex.toString());
    List<Subscriber> appendIndexList = await subRepo.findAllSubscribersWithPermitIndex(sub.topic, maxPageIndex);

    List acceptList = new List();
    List rejectList = new List();
    int maxLength = 1024;
    String cMapString = '';
    for (int index = 0; index < appendIndexList.length; index++){
      Subscriber tSub = appendIndexList[index];
      Map addressMap = {
        'addr':tSub.chatId
      };
      if (tSub.memberStatus == MemberStatus.MemberSubscribed){
        acceptList.add(addressMap);
      }
      else{
        rejectList.add(addressMap);
        /// todo check if any status is out of this judge
        // static const int DefaultNotMember = 0;
        // static const int MemberInvited = 1;
        // static const int MemberPublished = 2;
        // static const int MemberSubscribed = 3;
        // static const int MemberPublishRejected = 4;
        // static const int MemberJoinedButNotInvited = 5;
      }
      Map cMap = new Map();
      cMap['accept'] = acceptList;
      cMap['reject'] = rejectList;

      cMapString = jsonEncode(cMap);
      int currentLength = utf8.encode(cMapString).length;
      if (currentLength > maxLength){
        NLog.w('______MEET MAX:'+cMapString.toString());
        acceptList.clear();
        rejectList.clear();

        maxPageIndex += 1;
        acceptList.add(addressMap);
        cMap['accept'] = acceptList;
        cMapString = jsonEncode(cMap);
      }
    }
    double minerFee = 0;
    String groupTopicIdentifier = '__${maxPageIndex}__.__permission__';
    String theTopicHash = genTopicHash(topicName);

    try {
      var subHash = await NKNClientCaller.subscribe(
        identifier: groupTopicIdentifier,
        topicHash: theTopicHash,
        duration: 400000,
        fee: minerFee.toString(),
        meta: cMapString,
      );
      if (subHash != null) {
        NLog.w('Sub Hash is____' + subHash.toString());
      }
    } catch (e) {
      NLog.e('uploadPermissionMeta' + e.toString());
    }
  }

  // static Future<bool> checkMemberIsInGroup(Subscriber sub) async{
  //   int pageIndex = 0;
  //   if (sub.indexPermiPage > 0){
  //     pageIndex = sub.indexPermiPage;
  //   }
  //
  //   final owner = getPubkeyFromTopicOrChatId(sub.topic);
  //   String indexWithPubKey = '__${pageIndex}__.__permission__.'+owner;
  //   final topicHashed = genTopicHash(sub.topic);
  //
  //   var subscription =
  //       await NKNClientCaller.getSubscription(
  //     topicHash: topicHashed,
  //     subscriber: indexWithPubKey,
  //   );
  //
  //   final meta = subscription['meta'] as String;
  //   NLog.w('meta is____'+meta.toString());
  //
  //   final json = jsonDecode(meta);
  //   NLog.w('Json is____'+json.toString());
  //   final List accept = json["accept"];
  //   final List reject = json["reject"];
  //   if (accept.length > 0){
  //     for (int i = 0; i < accept.length; i++){
  //       Map memberInfo = accept[i];
  //       if (memberInfo['addr'] == sub.chatId){
  //         subRepo.updateMemberStatus(sub, MemberStatus.MemberSubscribed);
  //         return true;
  //       }
  //     }
  //   }
  //   var subs = await NKNClientCaller.getSubscribers(
  //       topicHash: topicHashed,
  //       offset: 0,
  //       limit: 10000,
  //       meta: true,
  //       txPool: true
  //   );
  //   if (subs == null){
  //     return false;
  //   }
  //   if (subs.keys.contains(sub.chatId)){
  //     return true;
  //   }
  //   return false;
  // }

  static Future<bool> isTopicExist(String topicName) async{
    Topic topic = await topicRepo.getTopicByName(topicName);
    if (topic != null){
      return true;
    }
    return false;
  }

  static testInsertMovies(String topicName) async{
    final topicHashed = genTopicHash(topicName);
    List<Subscriber> subs = await subRepo.getAllMemberByTopic('电影');
    /// testCase pull from channel '电影'
    List acceptList = new List();
    List rejectList = new List();
    List resultList = new List();
    int maxLength = 1024;
    int nextLength = 0;
    for (int index = 0; index < subs.length; index++){
      Subscriber tSub = subs[index];

      Map addressMap = {
        'addr':tSub.chatId
      };
      acceptList.add(addressMap);
      if (index+1 < subs.length){
        Subscriber nSub = subs[index+1];
        Map nAddress = {
          'addr':nSub.chatId
        };
        String nMapCL = jsonEncode(nAddress);
        nextLength = utf8.encode(nMapCL).length;
      }

      Map cMap = new Map();
      cMap['accept'] = acceptList;
      cMap['reject'] = rejectList;

      String cMapString = jsonEncode(cMap);
      int currentLength = utf8.encode(cMapString).length;
      if (currentLength+nextLength > maxLength){
        resultList.add(cMapString);

        NLog.w('______MEET MAX:'+cMapString.toString());
        acceptList.clear();
        rejectList.clear();
      }
    }
    double minerFee = 0;
    for (int rIndex = 0; rIndex < resultList.length; rIndex++){
      String cMapString = resultList[rIndex];
      String groupTopicKey = '__${rIndex}__.__permission__';
      String theTopicHash = genTopicHash(topicName);
      Timer(Duration(seconds: rIndex*20),() async {
        try {
          var subHash = await NKNClientCaller.subscribe(
            identifier: groupTopicKey,
            topicHash: theTopicHash,
            duration: 400000,
            fee: minerFee.toString(),
            meta: cMapString,
          );
          if (subHash != null){
            NLog.w('Sub Hash is____'+subHash.toString());
          }
          // else{
          //   break;
          // }
        } catch (e) {
          NLog.e('uploadPermissionMeta' + e.toString());
        }
      });
    }
  }

  static Future<void> pullPrivateSubscribers(String topicName) async{
    int pageIndex = 0;
    final topicHashed = genTopicHash(topicName.toString());

    final owner = getPubkeyFromTopicOrChatId(topicName);

    var subscribersMap = await NKNClientCaller.getSubscribers(
        topicHash: topicHashed,
        offset: 0,
        limit: 10000,
        meta: true,
        txPool: true
    );

    if (subscribersMap != null){
      for(int i = 0; i < subscribersMap.length; i++){
        String address = subscribersMap.keys.elementAt(i);
        Subscriber subscriber = await subRepo.getByTopicAndChatId(topicName, address);
        if (subscriber != null){
          if (subscriber.memberStatus < MemberStatus.MemberSubscribed){
            NLog.w('pullPrivateSubscribers is___'+address.toString());
            await subRepo.updateMemberStatus(subscriber, MemberStatus.MemberSubscribed);
          }
          else{
            NLog.w('Subscriber subscriber.memberStatus'+subscriber.memberStatus.toString());
          }
          if (subscriber.chatId.contains('.__permission__.')){
            await subRepo.delete(subscriber.topic, subscriber.chatId);
            /// do not need to handle private Group permission List for normal member.
            /// The List it under private group owner's control
            NLog.w('pullPrivateSubscribers MEET__'+address.toString());
          }
        }
        else{
          if (address.contains('.__permission__.')){
            /// do not need to handle private Group permission List for normal member.
            /// The List it under private group owner's control
            NLog.w('pullPrivateSubscribers MEET__'+address.toString());
          }
          else{
            Subscriber insertSub = Subscriber(
                topic: topicName,
                chatId: address,
                indexPermiPage: pageIndex,
                timeCreate: DateTime.now().millisecondsSinceEpoch,
                blockHeightExpireAt: -1,
                memberStatus: MemberStatus.MemberJoinedButNotInvited);
            subRepo.insertSubscriber(insertSub);
            NLog.w('pullPrivateSubscribers insert Subscriber to subscribed');
          }
        }
      }
    }

    /// Group member do not need to catch the invited but not subscribed member.
    if (owner != NKNClientCaller.currentChatId) {
      NLog.w('Not the private group owner, do not need to manager group members');
      return;
    }
  }

  static Future<void> groupOwnerUpdatePermissionData(String topicName) async{
    int pageIndex = 0;
    final topicHashed = genTopicHash(topicName.toString());

    final owner = getPubkeyFromTopicOrChatId(topicName);

    var subscribersMap = await NKNClientCaller.getSubscribers(
        topicHash: topicHashed,
        offset: 0,
        limit: 10000,
        meta: true,
        txPool: true
    );
    NLog.w('pullPrivateSubscribers getSubscribers is____'+subscribersMap.toString());
    while (true) {
      String indexWithPubKey = '__${pageIndex}__.__permission__.'+owner;

      var subscription =
      await NKNClientCaller.getSubscription(
        topicHash: topicHashed,
        subscriber: indexWithPubKey,
      );

      final meta = subscription['meta'] as String;
      NLog.w('meta is____'+indexWithPubKey.toString());
      if (meta.contains('__permission__')){
        break;
      }

      String subTopicIndex = '__${pageIndex}__.__permission__'+'.'+owner.toString();
      String subTopicHash = genTopicHash(subTopicIndex);
      var subs = await NKNClientCaller.getSubscribers(
          topicHash: subTopicHash,
          offset: 0,
          limit: 10000,
          meta: true,
          txPool: true
      );

      if (owner == NKNClientCaller.currentChatId){
        if (meta == null || meta.trim().isEmpty) {
          break;
        }
        try {
          final json = jsonDecode(meta);
          NLog.w('Json is____'+json.toString());
          final List accept = json["accept"];
          final List reject = json["reject"];
          if (accept != null) {
            if (accept.length > 0){
              if (accept[0] == "*"){
                Topic topic = await topicRepo.getTopicByName(topicName);
                topic.updateTopicToAcceptAll(true);
                break;
              }
            }
            for (var i = 0; i < accept.length; i++) {
              Map subMap = accept[i];
              String address = subMap['addr'];
              if (address.length < 64){
                NLog.w('Wrong!!!,invalid address! for pullPrivateSubscribers'+address.toString());
              }
              else if (address.contains('.__permission__.')){
                NLog.w('Wrong!!!,contains invalid __permission__'+address.toString());
              }
              else{
                Subscriber sub = await subRepo.getByTopicAndChatId(topicName, address);
                if (sub != null){
                  await subRepo.updatePermitIndex(sub, pageIndex);
                  if (sub.memberStatus < MemberStatus.MemberPublished){
                    await subRepo.updateMemberStatus(sub, MemberStatus.MemberPublished);
                  }
                }
                else{
                  sub = Subscriber(
                      topic: topicName,
                      chatId: address,
                      indexPermiPage: pageIndex,
                      timeCreate: DateTime.now().millisecondsSinceEpoch,
                      blockHeightExpireAt: -1,
                      memberStatus: MemberStatus.MemberPublished);
                  await subRepo.insertSubscriber(sub);
                }
              }
            }
          }
          if (reject != null) {
            for (var i = 0; i < reject.length; i++) {
              Map subMap = reject[i];
              String address = subMap['addr'];
              if (address.length < 64){
                NLog.w('Wrong!!!,reject invalid address! for pullPrivateSubscribers'+address.toString());
              }
              else if (address.contains('.__permission__.')){
                NLog.w('Wrong!!!,reject contains invalid __permission__'+address.toString());
              }
              else{
                Subscriber sub = await subRepo.getByTopicAndChatId(topicName, address);
                if (sub != null){
                  await subRepo.updatePermitIndex(sub, pageIndex);
                  await subRepo.updateMemberStatus(sub, MemberStatus.MemberPublishRejected);
                  NLog.w('pullPrivateSubscribers update To MemberPublishRejected!!!'+pageIndex.toString());
                }
                else{
                  NLog.w('pullPrivateSubscribers___!!!'+pageIndex.toString());
                  sub = Subscriber(
                      topic: topicName,
                      chatId: address,
                      indexPermiPage: pageIndex,
                      timeCreate: DateTime.now().millisecondsSinceEpoch,
                      blockHeightExpireAt: -1,
                      memberStatus: MemberStatus.MemberPublishRejected);
                  await subRepo.insertSubscriber(sub);
                }
              }
            }
          }
        } catch (e) {
          NLog.e("pullSubscribersPrivateChannel, e:" + e.toString());
        }
        ++pageIndex;
        NLog.w('PageIndex is-___'+pageIndex.toString());
      }
    }
  }

  static Future<List> pullSubscribersPublicChannel(String topicName) async {
    try {
      final topicHashed = genTopicHash(topicName);

      Map<String,dynamic> subscribers = await NKNClientCaller.getSubscribers(
          topicHash: topicHashed,
          offset: 0,
          limit: 10000,
          meta: false,
          txPool: true);

      if (subscribers.keys.contains(NKNClientCaller.currentChatId)){
        await GroupChatHelper.insertTopicIfNotExists(topicName);
      }

      for (String chatId in subscribers.keys) {
        NLog.w('pullSubscribersPublicChannel sub is___'+chatId.toString());
        Subscriber sub = Subscriber(
            id: 0,
            topic: topicName,
            chatId: chatId,
            timeCreate: DateTime.now().millisecondsSinceEpoch,
            blockHeightExpireAt: -1,
            memberStatus: MemberStatus.MemberSubscribed);
        await subRepo.insertSubscriber(sub);
      }
      Subscriber selfSub = Subscriber(
          id: 0,
          topic: topicName,
          chatId: NKNClientCaller.currentChatId,
          timeCreate: DateTime.now().millisecondsSinceEpoch,
          blockHeightExpireAt: -1,
          memberStatus: MemberStatus.MemberSubscribed);
      await subRepo.insertSubscriber(selfSub);

      List<Subscriber> dataList = await subRepo.getAllMemberByTopic(topicName);
      NLog.w('Find Members Count___'+dataList.length.toString()+'__forTopic__'+topicName);
      return dataList;
    } catch (e) {
      if (e != null) {
        NLog.w('group_chat_helper E:' + e.toString());
      }
      return null;
    }
  }
}