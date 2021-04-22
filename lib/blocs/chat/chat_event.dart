import 'package:equatable/equatable.dart';
import 'package:nmobile/model/entity/message.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object> get props => [];
}

class NKNChatOnMessageEvent extends ChatEvent {}

class ReceiveMessageEvent extends ChatEvent {
  final MessageSchema message;
  const ReceiveMessageEvent(this.message);
}

class SendMessageEvent extends ChatEvent {
  final MessageSchema message;
  const SendMessageEvent(this.message);
}

class RefreshMessageListEvent extends ChatEvent{
  final String targetId;
  const RefreshMessageListEvent({this.targetId});
}

class RefreshMessageChatEvent extends ChatEvent {
  final MessageSchema message;
  const RefreshMessageChatEvent(this.message);
}
