import 'package:nmobile/model/entity/message_list_model.dart';

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