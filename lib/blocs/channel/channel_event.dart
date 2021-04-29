abstract class ChannelMembersEvent {
  const ChannelMembersEvent();
}

class ChannelMemberCountEvent extends ChannelMembersEvent {
  final String topicName;
  ChannelMemberCountEvent(this.topicName);
}

class ChannelOwnMemberCountEvent extends ChannelMembersEvent{
  final String topicName;
  ChannelOwnMemberCountEvent(this.topicName);
}

class FetchChannelMembersEvent extends ChannelMembersEvent {
  final String topicName;
  FetchChannelMembersEvent(this.topicName);
}

class FetchMoreChannelMembersEvent extends ChannelMembersEvent{
  final String topicName;
  final int startIndex;
  FetchMoreChannelMembersEvent(this.topicName, this.startIndex);
}

class FetchOwnChannelMembersEvent extends ChannelMembersEvent {
  final String topicName;
  FetchOwnChannelMembersEvent(this.topicName);
}