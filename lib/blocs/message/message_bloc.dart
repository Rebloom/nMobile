

import 'package:bloc/bloc.dart';
import 'package:nmobile/blocs/message/message_event.dart';
import 'package:nmobile/blocs/message/message_state.dart';
import 'package:nmobile/model/datacenter/message_data_center.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/entity/message_list_model.dart';
import 'package:nmobile/utils/nlog_util.dart';

class MessageBloc extends Bloc<MessageEvent, MessageState> {
  @override
  MessageState get initialState => DefaultMessageState();

  @override
  Stream<MessageState> mapEventToState(MessageEvent event) async* {
    if (event is FetchMessageListEvent) {
      NLog.w('DefaultMessageState called');
      List<MessageListModel> messageList = await MessageListModel.getLastMessageList(event.start, 20);
      messageList.sort((a, b) => a.isTop
          ? (b.isTop ? -1 /*hold position original*/ : -1)
          : (b.isTop
          ? 1
          : b.lastReceiveTime.compareTo(a.lastReceiveTime)));
      NLog.w('FetchMessageListEvent is______'+messageList.length.toString());
      yield FetchMessageListState(messageList,event.start);
    }
    else if (event is FetchMessageListEndEvent){
      yield FetchMessageListEndState();
    }
    else if (event is UpdateMessageListEvent){
      NLog.w('Refresh UpdateMessageListEvent'+event.targetId.toString());
      MessageListModel model = await MessageListModel.updateMessageListModel(event.targetId);
      if (model == null){

      }
      else{
        NLog.w('Count__is______'+model.notReadCount.toString());
      }
      yield UpdateMessageListState(model);
    }
    else if (event is MarkMessageListAsReadEvent){
      MessageListModel model = await MessageListModel.markMessageListAsRead(event.model);
      yield UpdateMessageListState(model);
    }
  }
}
