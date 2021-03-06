import 'dart:io';
import 'dart:typed_data';

import 'package:nmobile/helpers/utils.dart';
import 'package:nmobile/model/db/nkn_data_manager.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/model/message_model.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MessageDataCenter {
  static updateMessagePid(Uint8List pid, String msgId) async {
    Database cdb = await NKNDataManager().currentDatabase();
    int result = await cdb.update(
      MessageSchema.tableName,
      {
        'pid': pid != null ? hexEncode(pid) : null,
      },
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
    if (result > 0) {
      NLog.d('updatePid success!__' + msgId.toString());
    } else {
      NLog.w('Wrong!!! updatePid Failed!!!' + msgId.toString());
      NLog.w('Wrong!!! updatePid Failed!!!' + result.toString());
    }
  }

  Future<int> testMessage() async {
    // b5dbb01b-0385-4545-806e-7515ee263a40

    Database cdb = await NKNDataManager().currentDatabase();

    var res = await cdb.query(
      MessageSchema.tableName,
      where: 'msg_id = ? AND type = ?',
      whereArgs: [
        'b5dbb01b-0385-4545-806e-7515ee263a40',
        ContentType.nknOnePiece
      ],
    );

    if (res.length > 0) {
      return res.length;
    }
    return 0;
  }

  static Future<bool> judgeMessagePid(String msgId) async {
    Database cdb = await NKNDataManager().currentDatabase();

    var res = await cdb.query(
      MessageSchema.tableName,
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );

    if (res != null && res.length > 0) {
      MessageSchema message = MessageSchema.parseEntity(res.first);
      if (message.pid != null && message.pid.length > 0) {
        return true;
      }
    }
    return null;
  }

  static Future<bool> removeOnePieceCombinedMessage(String msgId) async {
    Database cdb = await NKNDataManager().currentDatabase();

    var res = await cdb.query(
      MessageSchema.tableName,
      where: 'msg_id = ? AND type = ?',
      whereArgs: [msgId, ContentType.nknOnePiece],
    );

    if (res.length > 0) {
      for (int i = 0; i < res.length; i++) {
        MessageSchema onePiece = MessageSchema.parseEntity(res[i]);
        File oneFile = onePiece.content as File;
        if (oneFile.existsSync()) {
          oneFile.delete();
          NLog.w('removeOnePieceCombinedMessage DeleteFile__' +
              onePiece.index.toString());
        }
      }
    }

    var excuteCount = await cdb.delete(
      MessageSchema.tableName,
      where: 'msg_id = ? AND type = ?',
      whereArgs: [msgId, ContentType.nknOnePiece],
    );

    if (excuteCount > 0) {
      NLog.w('Remove OnePieceMessageCount__' + excuteCount.toString());
      return true;
    }
    return false;
  }

  static Future<List<MessageModel>> getAndReadTargetMessages(String targetId,
      int start) async {
    Database cdb = await NKNDataManager().currentDatabase();
    await cdb.update(
      MessageSchema.tableName,
      {
        'is_read': 1,
      },
      where: 'target_id = ? AND is_outbound = 0 AND is_read = 0',
      whereArgs: [targetId],
    );
    var res = await cdb.query(
      MessageSchema.tableName,
      columns: ['*'],
      orderBy: 'send_time desc',
      where: 'target_id = ? AND NOT type = ?',
      whereArgs: [targetId, ContentType.nknOnePiece],
      limit: 20,
      offset: start,
    );

    List<MessageModel> messages = <MessageModel>[];

    for (var i = 0; i < res.length; i++) {
      var messageItem = MessageSchema.parseEntity(res[i]);
      MessageModel model;
      if (!messageItem.isSendMessage() && messageItem.options != null) {
        NLog.w('messageItem.options is__'+messageItem.options.toString());
        if (messageItem.deleteTime == null &&
            messageItem.options['deleteAfterSeconds'] != null) {
          messageItem.deleteTime = DateTime.now().add(
              Duration(seconds: messageItem.options['deleteAfterSeconds']));
          cdb.update(
            MessageSchema.tableName,
            {
              'delete_time': messageItem.deleteTime.millisecondsSinceEpoch,
            },
            where: 'msg_id = ?',
            whereArgs: [messageItem.msgId],
          );
        }
      }
      model = await MessageModel.modelFromMessageFrom(messageItem);
      NLog.w('messageItem1 is ______'+model.messageEntity.contentType.toString());
      NLog.w('messageItem2 is ______'+model.messageEntity.content.toString());
      NLog.w('messageItem3 is ______'+model.contactEntity.getShowName.toString());

      if (model != null) {
        messages.add(model);
      }
    }
    if (messages.length > 0) {
      return messages;
    }
    return null;
  }

}
