

import 'package:bloc/bloc.dart';
import 'package:nmobile/blocs/message/message_event.dart';
import 'package:nmobile/blocs/message/message_state.dart';
import 'package:nmobile/model/entity/message_list_model.dart';
import 'package:nmobile/utils/nlog_util.dart';

class MessageBloc extends Bloc<MessageEvent, MessageState> {
  @override
  MessageState get initialState => DefaultMessageState();

  static final pageLength = 20;

  @override
  Stream<MessageState> mapEventToState(MessageEvent event) async* {
    if (event is FetchMessageListEvent) {
      List<MessageListModel> messageList = await MessageListModel.getLastMessageList(event.start, pageLength);
      messageList.sort((a, b) => a.isTop
          ? (b.isTop ? -1 /*hold position original*/ : -1)
          : (b.isTop
          ? 1
          : b.lastReceiveTime.compareTo(a.lastReceiveTime)));
      NLog.w('FetchMessageListEvent is______'+messageList.length.toString());
      yield FetchMessageListState(messageList,event.start);
    }
    else if (event is FetchMoreMessageListEvent){
      List<MessageListModel> messageList = await MessageListModel.getLastMessageList(event.start, pageLength);
      messageList.sort((a, b) => a.isTop
          ? (b.isTop ? -1 /*hold position original*/ : -1)
          : (b.isTop
          ? 1
          : b.lastReceiveTime.compareTo(a.lastReceiveTime)));
      NLog.w('FetchMoreMessageListEvent is______'+messageList.length.toString());
      yield FetchMoreMessageListState(messageList,event.start);
    }
    else if (event is FetchMessageListEndEvent){
      yield FetchMessageListEndState();
    }
    else if (event is UpdateMessageListEvent){
      MessageListModel model = await MessageListModel.updateMessageListModel(event.targetId);
      if (model == null){
        NLog.w('UpdateMessageListEvent Count is____null');
      }
      yield UpdateMessageListState(model);
    }
  }
}
