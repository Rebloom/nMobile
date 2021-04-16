
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

class UpdateSingleEvent extends MessageEvent{
  final String targetId;
  const UpdateSingleEvent(this.targetId);
}