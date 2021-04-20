import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/entity/message_list_model.dart';
import 'package:nmobile/model/entity/topic_repo.dart';

abstract class MessageState {
  const MessageState();
}

class FetchMessageListState extends MessageState {
  final List<MessageListModel> messageList;
  final int startIndex;
  const FetchMessageListState(this.messageList,this.startIndex);
}

class DefaultMessageState extends MessageState{
  const DefaultMessageState();
}

class FetchMessageListEndState extends MessageState{
  const FetchMessageListEndState();
}

class UpdateMessageListState extends MessageState{
  final MessageListModel updateModel;
  const UpdateMessageListState(this.updateModel);
}

class MarkMessageListAsReadState extends MessageState{
  final MessageListModel model;
  const MarkMessageListAsReadState(this.model);
}