
import 'package:flutter/material.dart';
import 'package:nmobile/model/db/nkn_data_manager.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MessageListModel {
  String targetId;
  String sender;
  String content;
  String contentType;
  DateTime lastReceiveTime;
  int notReadCount;
  bool isTop;

  Topic topic;
  ContactSchema contact;

  MessageListModel({
    this.targetId,
    this.sender,
    this.content,
    this.contentType,
    this.lastReceiveTime,
    this.notReadCount,
    this.isTop = false,
    this.topic,
    this.contact
  });

  static Future<MessageListModel> parseEntity(Map e) async {
    NLog.w('Content is______'+e.toString());
    var res = MessageListModel(
      targetId: e['target_id'],
      sender: e['sender'],
      content: e['content'],
      contentType: e['type'],
      lastReceiveTime: DateTime.fromMillisecondsSinceEpoch(e['receive_time']),
      notReadCount: e['not_read'] as int,
    );
    if (e['topic'] != null) {
      final repoTopic = TopicRepo();
      res.topic = await repoTopic.getTopicByName(e['topic']);
      res.contact = await ContactSchema.fetchContactByAddress(res.sender);
      res.isTop = res.topic?.isTop ?? false;

      if (res.topic == null){
        res.isTop = await ContactSchema.getIsTop(res.targetId);
        res.contact = await ContactSchema.fetchContactByAddress(res.targetId);
      }
    } else {
      if (res.targetId == null){
        NLog.w('Wrong!!!!! error msg is___'+e.toString());
        return null;
      }
      res.isTop = await ContactSchema.getIsTop(res.targetId);
      res.contact = await ContactSchema.fetchContactByAddress(res.targetId);
    }
    return res;
  }

  static Future<MessageListModel> updateMessageListModel(String targetId) async{
    Database cdb = await NKNDataManager().currentDatabase();

    var res = await cdb.query('Messages',
      where: 'target_id = ? AND is_outbound = 0 AND is_read = 0 AND type = ? AND type = ? AND type = ? AND type = ? AND type = ?',
      whereArgs: [
        targetId,
        ContentType.text,
        ContentType.textExtension,
        ContentType.media,
        ContentType.nknAudio,
        ContentType.nknImage
      ],
      orderBy: 'send_time desc',
    );

    if (res != null && res.length > 0){
      Map info = res[0];
      NLog.w('updateMessageListToRead info is____'+info.toString());
      MessageListModel model = await MessageListModel.parseEntity(info);
      model.notReadCount = res.length;
      NLog.w('updateMessageListToRead resLength is____'+res.length.toString());
      return model;
    }
    else{
      var countResult = await cdb.query('Messages',
        where: 'target_id = ? AND type = ? AND type = ? AND type = ? AND type = ? AND type = ?',
        whereArgs: [
          targetId,
          ContentType.text,
          ContentType.textExtension,
          ContentType.media,
          ContentType.nknAudio,
          ContentType.nknImage,
        ],
        orderBy: 'send_time desc',
      );
      if (countResult != null && countResult.length > 0){
        Map info = countResult[0];
        MessageListModel model = await MessageListModel.parseEntity(info);
        model.notReadCount = 0;
        return model;
      }
    }
    return null;
  }

  static Future<List<MessageListModel>> getLastMessageList(
      int start, int length) async {
    Database cdb = await NKNDataManager().currentDatabase();
    if (cdb == null) {
      return null;
    }

    var res = await cdb.query(
    '${MessageSchema.tableName} as m',
      columns: [
        'm.*',
        '(SELECT COUNT(id) from ${MessageSchema.tableName} WHERE target_id = m.target_id AND is_outbound = 0 AND is_read = 0 '
            'AND NOT type = "event:subscribe" '
            'AND NOT type = "nknOnePiece"'
            'AND NOT type = "event:contactOptions") as not_read',
        'MAX(send_time)'
      ],
      where:
      "type = ? or type = ? or type = ? or type = ? or type = ? or type = ? or type = ?",
      whereArgs: [
        ContentType.text,
        ContentType.textExtension,
        ContentType.media,
        ContentType.nknImage,
        ContentType.nknAudio,
        ContentType.channelInvitation,
        ContentType.eventSubscribe,
      ],
      groupBy: 'm.target_id',
      orderBy: 'm.send_time desc',
      limit: length,
      offset: start,
    );

    List<MessageListModel> list = <MessageListModel>[];
    for (var i = 0, length = res.length; i < length; i++) {
      var item = res[i];
      MessageListModel model = await MessageListModel.parseEntity(item);
      if (model != null){
        list.add(model);
      }
    }
    if (list.length > 0) {
      return list;
    }
    return null;
  }

  static Future<int> deleteTargetChat(String targetId) async {
    Database cdb = await NKNDataManager().currentDatabase();

    return await cdb.delete(MessageSchema.tableName,
        where: 'target_id = ?', whereArgs: [targetId]);
  }
}