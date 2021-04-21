import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flustars/flustars.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nmobile/blocs/auth/auth_bloc.dart';
import 'package:nmobile/blocs/auth/auth_event.dart';
import 'package:nmobile/blocs/auth/auth_state.dart';
import 'package:nmobile/blocs/chat/chat_bloc.dart';
import 'package:nmobile/blocs/chat/chat_state.dart';

import 'package:nmobile/blocs/message/message_bloc.dart';
import 'package:nmobile/blocs/message/message_event.dart';
import 'package:nmobile/blocs/message/message_state.dart';
import 'package:nmobile/blocs/nkn_client_caller.dart';
import 'package:nmobile/components/CommonUI.dart';
import 'package:nmobile/components/button.dart';
import 'package:nmobile/components/dialog/bottom.dart';
import 'package:nmobile/components/label.dart';
import 'package:nmobile/consts/colors.dart';
import 'package:nmobile/consts/theme.dart';
import 'package:nmobile/helpers/format.dart';
import 'package:nmobile/helpers/global.dart';
import 'package:nmobile/helpers/hash.dart';
import 'package:nmobile/helpers/local_storage.dart';
import 'package:nmobile/helpers/utils.dart';
import 'package:nmobile/l10n/localization_intl.dart';
import 'package:nmobile/model/datacenter/contact_data_center.dart';
import 'package:nmobile/model/datacenter/group_data_center.dart';
import 'package:nmobile/model/entity/message_list_model.dart';
import 'package:nmobile/model/entity/topic_repo.dart';
import 'package:nmobile/model/popular_channel.dart';
import 'package:nmobile/model/entity/contact.dart';
import 'package:nmobile/model/group_chat_helper.dart';
import 'package:nmobile/model/entity/message.dart';
import 'package:nmobile/screens/chat/authentication_helper.dart';
import 'package:nmobile/screens/chat/message_chat_page.dart';
import 'package:nmobile/utils/extensions.dart';
import 'package:nmobile/utils/image_utils.dart';
import 'package:nmobile/utils/log_tag.dart';
import 'package:nmobile/utils/nlog_util.dart';
import 'package:oktoast/oktoast.dart';

class MessageListPage extends StatefulWidget {
  final TimerAuth timerAuth;

  MessageListPage(this.timerAuth);

  @override
  MessageListPageState createState() => MessageListPageState();
}

class MessageListPageState extends State<MessageListPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin, Tag {
  List<MessageListModel> _messagesList = <MessageListModel>[];

  AuthBloc _authBloc;
  ChatBloc _chatBloc;
  MessageBloc _messageBloc;

  StreamSubscription _chatSubscription;
  ScrollController _scrollController = ScrollController();

  bool loading = false;
  List<PopularChannel> populars;
  bool isHideTip = false;

  int timeBegin = 0;
  int startIndex = 0;

  @override
  void initState() {
    super.initState();

    timeBegin = DateTime.now().millisecondsSinceEpoch;

    isHideTip = SpUtil.getBool(LocalStorage.WALLET_TIP_STATUS, defValue: false);
    populars = PopularChannel.defaultData();

    _authBloc = BlocProvider.of<AuthBloc>(context);
    _chatBloc = BlocProvider.of<ChatBloc>(context);
    _messageBloc = BlocProvider.of<MessageBloc>(context);

    _startRefreshMessage();

    _scrollController.addListener(() {
      double offsetFromBottom = _scrollController.position.maxScrollExtent -
          _scrollController.position.pixels;

      if (offsetFromBottom < 50 && !loading) {
        loading = true;
        _loadMore().then((v) {
          loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    super.dispose();
  }

  _updateTopicBlock() async {
    if (Global.upgradedGroupBlockHeight == true) {
      Global.upgradedGroupBlockHeight = false;
      _checkUnreadMessage();
      NKNClientCaller.fetchBlockHeight().then((blockHeight) {
        if (blockHeight == null || blockHeight == 0) {
          return;
        }
        TopicRepo().getAllTopics().then((topicList) {
          for (Topic topic in topicList) {
            if (topic.blockHeightExpireAt != null) {
              NLog.w('Check Topic:__' +
                  topic.topic +
                  '__' +
                  topic.blockHeightExpireAt.toString());
            } else {
              NLog.w('Wrong!!! topic.blockHeightExpireAt is null');
            }
            if (topic.blockHeightExpireAt == -1 ||
                topic.blockHeightExpireAt == null) {
              NLog.w('blockHeightExpireAt null or wrong!!!');
              final String topicHash = genTopicHash(topic.topicName);
              NKNClientCaller.getSubscription(
                      topicHash: topicHash,
                      subscriber: NKNClientCaller.currentChatId)
                  .then((subscription) {
                if (subscription['expiresAt'] != null) {
                  TopicRepo().updateOwnerExpireBlockHeight(topic.topicName,
                      int.parse(subscription['expiresAt'].toString()));
                  NLog.w('UpgradeTopic__' +
                      topic.topic +
                      'Success' +
                      '__' +
                      subscription.toString());
                }
              });
            } else if ((blockHeight - topic.blockHeightExpireAt) > Global.topicBlockHeightExpireWarnHeight) {
              String topicName = topic.topic;
              if (topic.isPrivateTopic() == false) {
                GroupDataCenter.subscribeTopic(
                    topicName: topicName,
                    chatBloc: _chatBloc,
                    callback: (success, e) {
                      if (success) {
                        NLog.w('update topic blockHeight success');
                      } else {
                        NLog.w('update topic blockHeight Failed E:' +
                            e.toString());
                      }
                    });

                final String topicHash = genTopicHash(topic.topicName);
                NKNClientCaller.getSubscription(
                        topicHash: topicHash,
                        subscriber: NKNClientCaller.currentChatId)
                    .then((subscription) {
                  NLog.w('getSubscription_____' + subscription.toString());
                  if (subscription['expiresAt'] != null) {
                    TopicRepo().updateOwnerExpireBlockHeight(topic.topicName,
                        int.parse(subscription['expiresAt'].toString()));
                    if (topic.topic != null && subscription != null) {
                      NLog.w('UpdateTopic__' +
                          topic.topic +
                          'Success' +
                          '__' +
                          subscription.toString());
                    } else {
                      NLog.w('Wrong!!! topic.topic or subscription is null');
                    }
                  }
                });
              } else {
                /// Update PrivateChannel Logic

              }
            } else {
              if (topic.topic != null) {
                NLog.w('topic is inTime__' + topic.topic);
              }
            }
          }
        });
      });
    }
  }

  _checkUnreadMessage() async{
    List unreadList = await MessageSchema.findAllUnreadMessages();
    for (MessageSchema message in unreadList){
      if (message.contentType == ContentType.text ||
          message.contentType == ContentType.textExtension ||
          message.contentType == ContentType.media ||
          message.contentType == ContentType.nknImage ||
          message.contentType == ContentType.nknAudio ||
          message.contentType == ContentType.media){
          /// for other types mark them as Read.
      }
      else{
        await message.markMessageRead();
      }
      if (message.topic != null){
        bool topicExist = await GroupDataCenter.isTopicExist(message.topic);
        if (topicExist == false){
          if (isPrivateTopicReg(message.topic)){
            await message.markMessageRead();
            GroupDataCenter.pullPrivateSubscribers(message.topic);
          }
          else{
            GroupDataCenter.pullSubscribersPublicChannel(message.topic);
          }
        }
      }
    }
  }

  _startRefreshMessage() async {
    _updateTopicBlock();

    startIndex = 0;
    _messageBloc.add(FetchMessageListEvent(startIndex));
    NLog.w('_startRefreshMessage called is____'+startIndex.toString());
  }

  Future _loadMore() async {
    if (Global.clientCreated == false) {
      return;
    }
    if (startIndex != _messagesList.length){
      startIndex = _messagesList.length;
    }
    else{
      _messageBloc.add(FetchMessageListEndEvent());
    }
    NLog.w('_loadMore startIndex is____'+startIndex.toString());
    _messageBloc.add(FetchMessageListEvent(startIndex));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        if (authState is AuthToUserState) {
          NLog.w('AuthToUserState is_____'+authState.toString());
          startIndex = 0;
          _messageBloc.add(FetchMessageListEvent(startIndex));
          _authBloc.add(AuthToFrontEvent());
        }
        return BlocBuilder<ChatBloc, ChatState>(
          builder: (context, chatState) {
            if (chatState is MessageUpdateState) {
              if (chatState.message != null){
                NLog.w('chatState message from is_____'+chatState.message.messageEntity.from.toString());
              }
              else{
                NLog.w('chatState.message is_____null');
              }
              if (chatState.target == null){
                _startRefreshMessage();

                NLog.w('chatState.target is_____null');
              }
              else{
                _messageBloc.add(UpdateMessageListEvent(chatState.target));
              }
            }
            return BlocBuilder<MessageBloc, MessageState>(
              builder: (context, messageState){
                NLog.w('messageState state is______'+messageState.toString());
                if (_messagesList == null){
                  _messagesList = new List();
                }
                if (messageState is FetchMessageListState){
                  if (startIndex == 0){
                    _messagesList = messageState.messageList;
                  }
                  else{
                    if (messageState.messageList != null){
                      if (_messagesList.length < startIndex+messageState.messageList.length){
                        _messagesList += messageState.messageList;
                      }
                    }
                  }
                  return _messageListWidget();
                }
                else if (messageState is UpdateMessageListState){
                  NLog.w('UpdateMessageListState called');
                  if (messageState.updateModel == null){
                    _startRefreshMessage();
                  }
                  else{
                    int replaceIndex = -1;
                    for (int i = 0; i < _messagesList.length; i++){
                      MessageListModel model = _messagesList[i];
                      if (model.targetId == messageState.updateModel.targetId){
                        _messagesList.removeAt(i);
                        _messagesList.insert(i, messageState.updateModel);
                        replaceIndex = i;
                        break;
                      }
                    }
                    if (replaceIndex > 0){
                      /// todo Need refreshList
                    }
                  }
                }
                else if (messageState is MarkMessageListAsReadState){
                  MessageListModel updateModel = messageState.model;
                  for (int i = 0; i < _messagesList.length; i++){
                    MessageListModel model = _messagesList[i];
                    if (model.targetId == updateModel.targetId){
                      _messagesList.removeAt(i);
                      _messagesList.insert(i, updateModel);
                      break;
                    }
                  }
                }
                if (_messagesList.length > 0){
                  return _messageListWidget();
                }
                return _noMessageWidget();
              },
            );
          },
        );
      },
    );
  }

  showMenu(MessageListModel item, int index) {
    showDialog<Null>(
      context: context,
      builder: (BuildContext context) {
        return new SimpleDialog(
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6))),
          children: [
            SimpleDialogOption(
              child: Row(
                children: [
                  Icon(item.isTop
                          ? Icons.vertical_align_bottom
                          : Icons.vertical_align_top)
                      .pad(r: 12),
                  Text(item.isTop
                      ? NL10ns.of(context).top_cancel
                      : NL10ns.of(context).top),
                ],
              ).pad(t: 8, b: 4),
              onPressed: () async {
                Navigator.of(context).pop();
                final top = !item.isTop;
                final numChanges = await (item.topic == null
                    ? ContactSchema.setTop(item.targetId, top)
                    : TopicRepo().updateIsTop(item.topic.topic,
                        top)); // TopicSchema.setTop(db, item.topic.topic, top));
                if (numChanges > 0) {
                  setState(() {
                    item.isTop = top;
                    _messagesList.remove(item);
                    _messagesList.insert(0, item);
                  });
                }
              },
            ),
            SimpleDialogOption(
              child: Row(
                children: [
                  Icon(Icons.delete_outline).pad(r: 12),
                  Text(NL10ns.of(context).delete),
                ],
              ).pad(t: 4, b: 8),
              onPressed: () {
                Navigator.of(context).pop();
                MessageListModel.deleteTargetChat(item.targetId).then((numChanges) {
                  if (numChanges > 0) {
                    setState(() {
                      _messagesList.remove(item);
                    });
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _noMessageWidget() {
    return Flex(
      direction: Axis.vertical,
      children: <Widget>[
        Expanded(
          flex: 1,
          child: Padding(
            padding: EdgeInsets.only(top: 0),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Container(
                    child: Flex(
                      direction: Axis.vertical,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Label(
                              NL10ns.of(context).popular_channels,
                              type: LabelType.h3,
                              textAlign: TextAlign.left,
                            ).pad(l: 20)
                          ],
                        ),
                        Container(
                          height: 188,
                          margin: 0.pad(t: 8),
                          child: ListView.builder(
                              itemCount: populars.length,
                              scrollDirection: Axis.horizontal,
                              itemBuilder: (context, index) {
                                return getPopularItemView(
                                    index, populars.length, populars[index]);
                              }),
                        ),
                        Expanded(
                          flex: 0,
                          child: Column(
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.only(top: 32),
                                child: Label(
                                  NL10ns.of(context).chat_no_messages_title,
                                  type: LabelType.h2,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.only(top: 8, left: 0, right: 0),
                                child: Label(
                                  NL10ns.of(context).chat_no_messages_desc,
                                  type: LabelType.bodyRegular,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            ],
                          ),
                        ),
                        Button(
                          width: -1,
                          height: 54,
                          padding: 0.pad(l: 36, r: 36),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              loadAssetIconsImage('pencil',
                                      width: 24,
                                      color: DefaultTheme.backgroundLightColor)
                                  .pad(r: 12),
                              Label(NL10ns.of(context).new_message,
                                  type: LabelType.h3)
                            ],
                          ),
                          onPressed: () async {
                            if (TimerAuth.authed) {
                              var address = await BottomDialog.of(context)
                                  .showInputAddressDialog(
                                      title: NL10ns.of(context).new_whisper,
                                      hint: NL10ns.of(context)
                                          .enter_or_select_a_user_pubkey);
                              if (address != null) {
                                ContactSchema contact = ContactSchema(
                                    type: ContactType.stranger,
                                    clientAddress: address);
                                await contact.insertContact();
                                // _pushToSingleChat(contact);
                                _routeToChatPage(contact.clientAddress, false);
                              }
                            } else {
                              widget.timerAuth.onCheckAuthGetPassword(context);
                            }
                          },
                        ).pad(t: 54),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageListWidget() {
    return SafeArea(
      child: Flex(
        direction: Axis.vertical,
        children: [
          getTipView(),
          Expanded(
            flex: 1,
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: 72),
              controller: _scrollController,
              itemCount: _messagesList.length,
              itemBuilder: (BuildContext context, int index) {
                var item = _messagesList[index];
                Widget widget;
                if (item.topic != null) {
                  widget = getTopicItemView(item);
                } else {
                  widget = getSingleChatItemView(item);
                }
                return InkWell(
                  onLongPress: () {
                    showMenu(item, index);
                  },
                  child: widget,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget getPopularItemView(int index, int length, PopularChannel model) {
    return Container(
      child: Container(
        width: 120,
        height: 120,
        margin: 8.pad(l: 20, r: index == length - 1 ? 20 : 12),
        decoration: BoxDecoration(
            color: DefaultTheme.backgroundColor2,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Container(
              margin: 0.pad(t: 20),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: model.titleBgColor,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                child: Label(
                  model.title,
                  type: LabelType.h3,
                  color: model.titleColor,
                ),
              ),
            ),
            SizedBox(height: 6.h),
            Label(
              model.subTitle,
              type: LabelType.h4,
            ),
            SizedBox(height: 6.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 90.w,
                  padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 6.w),
                  decoration: BoxDecoration(
                      color: Color(0xFF5458F7),
                      borderRadius: BorderRadius.circular(100)),
                  child: InkWell(
                    onTap: () {
                      if (TimerAuth.authed) {
                        _subscription(model);
                      } else {
                        widget.timerAuth.onCheckAuthGetPassword(context);
                      }
                    },
                    child: Center(
                      child: Text(
                        NL10ns.of(context).subscribe,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  _subscription(PopularChannel popular) async {
    EasyLoading.show();
    GroupDataCenter.subscribeTopic(
        topicName: popular.topic,
        chatBloc: _chatBloc,
        callback: (success, e) async {
          EasyLoading.dismiss();
          if (success) {
            _routeToChatPage(popular.topic, true);
          } else {
            if (e
                .toString()
                .contains('duplicate subscription exist in block')) {
              _routeToChatPage(popular.topic, true);
            } else {
              showToast(e.toString());
            }
          }
        });
    Timer(Duration(seconds: 5), () {
      EasyLoading.dismiss();
    });
  }

  getTipView() {
    if (isHideTip) {
      return Container();
    } else {
      return Container(
        margin: 20.pad(t: 25, b: 0),
        padding: 0.pad(b: 16),
        width: double.infinity,
        decoration: BoxDecoration(
            color: DefaultTheme.backgroundColor2,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colours.blue_0f_a1p,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                  child: loadAssetIconsImage('lock',
                      width: 24, color: DefaultTheme.primaryColor)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Label(
                    NL10ns.of(context).private_messages,
                    type: LabelType.h3,
                  ).pad(t: 16),
                  Label(
                    NL10ns.of(context).private_messages_desc,
                    type: LabelType.bodyRegular,
                    softWrap: true,
                  ).pad(t: 4),
                  Label(
                    NL10ns.of(context).learn_more,
                    type: LabelType.bodySmall,
                    color: DefaultTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ).pad(t: 6),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                SpUtil.putBool(LocalStorage.WALLET_TIP_STATUS, true);
                setState(() {
                  isHideTip = true;
                });
              },
              child: loadAssetIconsImage('close',
                      width: 16, color: Colours.gray_81)
                  .center
                  .sized(w: 48, h: 48),
            )
          ],
        ),
      );
    }
  }

  Widget _topLabelWidget(String topicName) {
    return Label(
      topicName,
      type: LabelType.h3,
      fontWeight: FontWeight.w500,
    );
  }

  Widget getTopicItemView(MessageListModel item) {
    ContactSchema contact = item.contact;
    Widget contentWidget;
    LabelType bottomType = LabelType.bodySmall;
    String draft = '';
    if (NKNClientCaller.currentChatId != null) {
      LocalStorage.getChatUnSendContentFromId(
          NKNClientCaller.currentChatId, item.targetId);
    }
    if (draft != null && draft.length > 0) {
      contentWidget = Row(
        children: <Widget>[
          Label(
            NL10ns.of(context).placeholder_draft,
            type: LabelType.bodySmall,
            color: Colors.red,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(width: 5),
          Label(
            draft,
            type: bottomType,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (item.contentType == ContentType.nknImage ||
        item.contentType == ContentType.media) {
      contentWidget = Padding(
        padding: const EdgeInsets.only(top: 0),
        child: Row(
          children: <Widget>[
            Label(
              contact.getShowName + ': ',
              maxLines: 1,
              type: LabelType.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            loadAssetIconsImage('image',
                width: 14, color: DefaultTheme.fontColor2),
          ],
        ),
      );
    } else if (item.contentType == ContentType.channelInvitation) {
      contentWidget = Label(
        contact.getShowName + ': ' + NL10ns.of(context).channel_invitation,
        type: bottomType,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (item.contentType == ContentType.eventSubscribe) {
      contentWidget = Label(
        contact.getShowName + NL10ns.of(context).joined_channel,
        maxLines: 1,
        type: bottomType,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      contentWidget = Label(
        contact.getShowName + ': ' + item.content,
        maxLines: 1,
        type: bottomType,
        overflow: TextOverflow.ellipsis,
      );
    }
    List<Widget> topicWidget = [
      _topLabelWidget(item.topic.topicShort),
    ];
    if (item.topic.isPrivateTopic()) {
      topicWidget.insert(
          0,
          loadAssetIconsImage('lock',
              width: 18, color: DefaultTheme.primaryColor));
    }
    return InkWell(
      onTap: () async {
        _routeToChatPage(item.topic.topic, true);
      },
      child: Container(
        color: item.isTop ? Colours.light_fb : Colours.transparent,
        height: 72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: EdgeInsets.only(left: 16, right: 16),
              child: CommonUI.avatarWidget(
                radiusSize: 24,
                topic: item.topic,
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            width: 0.6,
                            color: item.isTop
                                ? Colours.light_e5
                                : Colours.light_e9))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: topicWidget),
                          contentWidget.pad(t: 6),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Label(
                          Format.timeFormat(item.lastReceiveTime),
                          type: LabelType.bodySmall,
                          fontSize: DefaultTheme.chatTimeSize,
                        ).pad(r: 20, b: 6),
                        _unReadWidget(item),
                      ],
                    ).pad(l: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unReadWidget(MessageListModel item) {
    String countStr = item.notReadCount.toString();
    if (item.notReadCount > 999) {
      countStr = '999+';
      return Container(
        margin: EdgeInsets.only(right: 15),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Container(
              color: Colours.purple_57,
              height: 25,
              width: 25,
              child: Center(
                child: Text(
                  countStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              )),
        ),
      );
    }
    double numWidth = 25;
    if (item.notReadCount > 99) {
      numWidth = 50;
    }
    if (item.notReadCount > 0) {
      return Container(
        margin: EdgeInsets.only(right: 15),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Container(
              color: Colours.purple_57,
              height: 25,
              width: numWidth,
              child: Center(
                child: Text(
                  countStr,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              )),
        ),
      );
    }
    return Container();
  }

  _routeToChatPage(String targetId,bool group) async{
    MessageListModel updateModel;
    for (MessageListModel model in _messagesList){
      if (model.targetId == targetId){
        updateModel = model;
        break;
      }
    }
    var argument;
    if (group){
      Topic topic = await GroupChatHelper.fetchTopicInfoByName(targetId);
      argument = topic;
    }
    else{
      ContactSchema contactInfo = await ContactSchema.fetchContactByAddress(targetId);
      argument = contactInfo;
    }
    Navigator.of(context).pushNamed(MessageChatPage.routeName,
        arguments: argument).then((value) {
      NLog.w('MarkMessageListAsReadEvent called____'+targetId);
      if (updateModel != null){
        _messageBloc.add(MarkMessageListAsReadEvent(updateModel));
      }
      // _chatBloc.add(RefreshMessageListEvent(targetId: targetId));
      if (value == true) {
        NLog.w('_routeToGroupChatPage called____');
        _startRefreshMessage();
      }
    });
  }

  Widget getSingleChatItemView(MessageListModel item) {
    LabelType bottomType = LabelType.bodySmall;

    ContactSchema contact = item.contact;
    if (contact == null){
      NLog.w('Target Id is null___'+item.targetId.toString());
      return Container();
    }
    Widget contentWidget;
    String draft = LocalStorage.getChatUnSendContentFromId(
        NKNClientCaller.currentChatId, item.targetId);
    if (draft != null && draft.length > 0) {
      contentWidget = Row(
        children: <Widget>[
          Label(
            NL10ns.of(context).placeholder_draft,
            type: LabelType.bodySmall,
            color: Colors.red,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(width: 5.w),
          Label(
            draft,
            type: LabelType.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (item.contentType == ContentType.nknImage ||
        item.contentType == ContentType.media) {
      contentWidget = Padding(
        padding: const EdgeInsets.only(top: 0),
        child: Row(
          children: <Widget>[
            loadAssetIconsImage('image',
                width: 16.w, color: DefaultTheme.fontColor2),
          ],
        ),
      );
    } else if (item.contentType == ContentType.nknAudio) {
      contentWidget = Padding(
        padding: const EdgeInsets.only(top: 0),
        child: Row(
          children: <Widget>[
            loadAssetIconsImage('microphone',
                width: 16.w, color: DefaultTheme.fontColor2),
          ],
        ),
      );
    } else if (item.contentType == ContentType.channelInvitation) {
      contentWidget = Label(
        NL10ns.of(context).channel_invitation,
        maxLines: 1,
        type: bottomType,
        overflow: TextOverflow.ellipsis,
      );
    } else if (item.contentType == ContentType.eventSubscribe) {
      contentWidget = Label(
        NL10ns.of(context).joined_channel,
        maxLines: 1,
        type: bottomType,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      contentWidget = Label(
        item.content,
        type: bottomType,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }
    return InkWell(
      onTap: () {
        _routeToChatPage(item.contact.clientAddress, false);
        // _pushToSingleChat(item);
      },
      child: Container(
        color: item.isTop ? Colours.light_fb : Colours.transparent,
        height: 72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: EdgeInsets.only(left: 16, right: 16),
              child: CommonUI.avatarWidget(
                radiusSize: 24,
                contact: contact,
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            width: 0.6,
                            color: item.isTop
                                ? Colours.light_e5
                                : Colours.light_e9))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _topLabelWidget(contact.getShowName),
                          contentWidget.pad(t: 6),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Label(
                          Format.timeFormat(item.lastReceiveTime),
                          type: LabelType.bodySmall,
                          fontSize: DefaultTheme.chatTimeSize,
                        ).pad(r: 20, b: 6),
                        _unReadWidget(item),
                      ],
                    ).pad(l: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
