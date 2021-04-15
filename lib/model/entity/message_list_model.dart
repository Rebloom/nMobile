
import 'package:nmobile/blocs/nkn_client_caller.dart';
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
        return null;
      }
      res.isTop = await ContactSchema.getIsTop(res.targetId);
      res.contact = await ContactSchema.fetchContactByAddress(res.targetId);
    }
    return res;
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
        '(SELECT COUNT(id) from ${MessageSchema.tableName} WHERE target_id = m.target_id AND is_outbound = 0 AND is_read = 0 AND NOT type = "event:subscribe" AND NOT type = "nknOnePiece") as not_read',
        'MAX(send_time)'
      ],
      where:
      "type = ? or type = ? or type = ? or type = ? or type = ? or type = ? or type = ?",
      whereArgs: [
        ContentType.text,
        ContentType.textExtension,
        ContentType.nknImage,
        ContentType.channelInvitation,
        ContentType.eventSubscribe,
        ContentType.media,
        ContentType.nknAudio
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