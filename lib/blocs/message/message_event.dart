
abstract class MessageEvent {
  const MessageEvent();
}

class FetchMessageListEvent extends MessageEvent {
  final int start;
  const FetchMessageListEvent(this.start);
}

class FetchMoreMessageListEvent extends MessageEvent{
  final int start;
  const FetchMoreMessageListEvent(this.start);
}

class FetchMessageListEndEvent extends MessageEvent{
  const FetchMessageListEndEvent();
}

class UpdateMessageListEvent extends MessageEvent{
  final String targetId;
  const UpdateMessageListEvent(this.targetId);
}
