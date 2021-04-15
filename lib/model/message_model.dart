
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/entity/message.dart';

class MessageModel {
  MessageSchema messageEntity;
  ContactSchema contactEntity;

  MessageModel(this.messageEntity,this.contactEntity);

  static Future<MessageModel> modelFromMessageFrom(MessageSchema messageModel) async{
    ContactSchema showContact = await ContactSchema.fetchContactByAddress(messageModel.from);

    MessageModel rModel = MessageModel(messageModel, showContact);
    return rModel;
  }
}