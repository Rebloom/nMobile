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


// class GetAndReadMessages extends ChatEvent {
//   final String target;
//
//   const GetAndReadMessages({this.target});
// }
//
//
// class MarkMessageListAsReadEvent extends MessageEvent{
//   final String targetId;
//   const MarkMessageListAsReadEvent(this.targetId);
// }
//
// class RefreshMessageListEvent extends MessageEvent {
//   final String targetId;
//   const RefreshMessageListEvent({this.targetId});
// }
//
// class ReceivedMessageChatEvent extends MessageEvent{
//   final MessageSchema message;
//   const ReceivedMessageChatEvent(this.message);
// }
//
// class RefreshMessageChatEvent extends MessageEvent {
//   final MessageSchema message;
//   const RefreshMessageChatEvent(this.message);
// }
