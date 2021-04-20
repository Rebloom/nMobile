
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/model/entity/message_list_model.dart';

abstract class MessageEvent {
  const MessageEvent();
}

class FetchMessageListEvent extends MessageEvent {
  final int start;
  const FetchMessageListEvent(this.start);
}

class FetchMessageListEndEvent extends MessageEvent{
  const FetchMessageListEndEvent();
}

class UpdateMessageListEvent extends MessageEvent{
  final String targetId;
  const UpdateMessageListEvent(this.targetId);
}

class MarkMessageListAsReadEvent extends MessageEvent{
  final MessageListModel model;
  const MarkMessageListAsReadEvent(this.model);
}