import 'package:nmobile/model/db/nkn_data_manager.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MessageItem {
  String targetId;
  String sender;
  Topic topic;
  String content;
  String contentType;
  DateTime lastReceiveTime;
  int notReadCount;
  bool isTop;

  MessageItem({
    this.targetId,
    this.sender,
    this.content,
    this.topic,
    this.contentType,
    this.lastReceiveTime,
    this.notReadCount,
    this.isTop = false,
  });

  static Future<MessageItem> parseEntity(Map e) async {
    var res = MessageItem(
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
      res.isTop = res.topic?.isTop ?? false;
    } else {
      res.isTop = await ContactSchema.getIsTop(res.targetId);
    }
    return res;
  }

  static Future<List<MessageItem>> getLastMessageList(
      int start, int length) async {
    Database cdb = await NKNDataManager().currentDatabase();
    if (cdb == null) {
      return null;
    }
    var res = await cdb.query(
      '${MessageSchema.tableName} as m',
      columns: [
        'm.*',
        '(SELECT COUNT(id) from ${MessageSchema.tableName} WHERE target_id = m.target_id AND is_outbound = 0 AND is_read = 0 AND NOT type = "nknOnePiece") as not_read',
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

    List<MessageItem> list = <MessageItem>[];
    for (var i = 0, length = res.length; i < length; i++) {
      var item = res[i];
      list.add(await MessageItem.parseEntity(item));
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
