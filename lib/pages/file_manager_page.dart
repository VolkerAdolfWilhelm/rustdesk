import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:provider/provider.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:path/path.dart' as Path;

import '../common.dart';
import '../models/model.dart';
import '../widgets/dialog.dart';

class FileManagerPage extends StatefulWidget {
  FileManagerPage({Key? key, required this.id}) : super(key: key);
  final String id;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  final model = FFI.fileModel;
  final _selectedItems = SelectedItems();
  Timer? _interval;
  Timer? _timer;
  var _reconnects = 1;
  final _breadCrumbScroller = ScrollController();

  @override
  void initState() {
    super.initState();
    showLoading(translate('Connecting...'));
    FFI.connect(widget.id, isFileTransfer: true);

    final res = FFI.getByName("read_dir", FFI.getByName("get_home_dir"));
    debugPrint("read_dir local :$res");
    model.tryUpdateDir(res, true);

    _interval = Timer.periodic(Duration(milliseconds: 30),
            (timer) => FFI.ffiModel.update(widget.id, context, handleMsgBox));
  }

  @override
  void dispose() {
    model.clear();
    _interval?.cancel();
    FFI.close();
    EasyLoading.dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Consumer<FileModel>(builder: (_context, _model, _child) {
        return WillPopScope(
            onWillPop: () async {
              if (model.selectMode) {
                model.toggleSelectMode();
              } else {
                goBack();
              }
              return false;
            },
            child: Scaffold(
              backgroundColor: MyTheme.grayBg,
              appBar: AppBar(
                leading: Row(children: [
                  IconButton(icon: Icon(Icons.arrow_back), onPressed: goBack),
                  IconButton(icon: Icon(Icons.close), onPressed: clientClose),
                ]),
                leadingWidth: 200,
                centerTitle: true,
                title: Text(translate(model.isLocal ? "Local" : "Remote")),
                actions: [
                  IconButton(
                    icon: Icon(Icons.change_circle),
                    onPressed: () => model.togglePage(),
                  )
                ],
              ),
              body: body(),
              bottomSheet: bottomSheet(),
            ));
      });

  bool needShowCheckBox() {
    if (!model.selectMode) {
      return false;
    }
    return !_selectedItems.isOtherPage(model.isLocal);
  }

  Widget body() {
    final isLocal = model.isLocal;
    final fd = model.currentDir;
    final entries = fd.entries;
    return Column(children: [
      headTools(),
      Expanded(
          child: ListView.builder(
            itemCount: entries.length + 1,
            itemBuilder: (context, index) {
              if (index >= entries.length) {
                // 添加尾部信息 文件统计信息等
                // 添加快速返回上部
                // 使用 bottomSheet 提示以选择的文件数量 点击后展开查看更多
                return listTail();
              }
              var selected = false;
              if (model.selectMode) {
                selected = _selectedItems.contains(entries[index]);
              }
              var sizeStr = "";
              if(entries[index].isFile){
                final size = entries[index].size;
                if(size< 1024){
                  sizeStr += size.toString() + "B";
                }else if(size< 1024 * 1024){
                  sizeStr += (size/1024).toStringAsFixed(2) + "kB";
                }else if(size < 1024 * 1024 * 1024){
                  sizeStr += (size/1024/1024).toStringAsFixed(2) + "MB";
                }else if(size < 1024 * 1024 * 1024 * 1024){
                  sizeStr += (size/1024/1024/1024).toStringAsFixed(2) + "GB";
                }
              }
              return Card(
                child: ListTile(
                  leading: Icon(
                      entries[index].isFile ? Icons.feed_outlined : Icons
                          .folder,
                      size: 40),

                  title: Text(entries[index].name),
                  selected: selected,
                  subtitle: Text(
                      entries[index].lastModified().toString().replaceAll(
                          ".000", "") + "   " + sizeStr,style: TextStyle(fontSize: 12,color: MyTheme.darkGray),),
                  trailing: needShowCheckBox()
                      ? Checkbox(
                      value: selected,
                      onChanged: (v) {
                        if (v == null) return;
                        if (v && !selected) {
                          _selectedItems.add(isLocal, entries[index]);
                        } else if (!v && selected) {
                          _selectedItems.remove(entries[index]);
                        }
                        setState(() {});
                      })
                      : null,
                  onTap: () {
                    if (model.selectMode &&
                        !_selectedItems.isOtherPage(isLocal)) {
                      if (selected) {
                        _selectedItems.remove(entries[index]);
                      } else {
                        _selectedItems.add(isLocal, entries[index]);
                      }
                      setState(() {});
                      return;
                    }
                    if (entries[index].isDirectory) {
                      model.openDirectory(entries[index].path);
                      breadCrumbScrollToEnd();
                    } else {
                      // Perform file-related tasks.
                    }
                  },
                  onLongPress: () {
                    _selectedItems.clear();
                    model.toggleSelectMode();
                    if (model.selectMode) {
                      _selectedItems.add(isLocal, entries[index]);
                    }
                    setState(() {});
                  },
                ),
              );
            },
          ))
    ]);
  }

  goBack() {
    model.goToParentDirectory();
  }

  void handleMsgBox(Map<String, dynamic> evt, String id) {
    var type = evt['type'];
    var title = evt['title'];
    var text = evt['text'];
    if (type == 're-input-password') {
      wrongPasswordDialog(id);
    } else if (type == 'input-password') {
      enterPasswordDialog(id);
    } else {
      var hasRetry = evt['hasRetry'] == 'true';
      print(evt);
      showMsgBox(type, title, text, hasRetry);
    }
  }

  void showMsgBox(String type, String title, String text, bool hasRetry) {
    msgBox(type, title, text);
    if (hasRetry) {
      _timer?.cancel();
      _timer = Timer(Duration(seconds: _reconnects), () {
        FFI.reconnect();
        showLoading(translate('Connecting...'));
      });
      _reconnects *= 2;
    } else {
      _reconnects = 1;
    }
  }

  breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      _breadCrumbScroller.animateTo(
          _breadCrumbScroller.position.maxScrollExtent,
          duration: Duration(milliseconds: 200),
          curve: Curves.fastLinearToSlowEaseIn);
    });
  }

  Widget headTools() =>
      Container(
          child: Row(
            children: [
              Expanded(
                  child: BreadCrumb(
                    items: getPathBreadCrumbItems(() =>
                        debugPrint("pressed home"),
                            (e) => debugPrint("pressed url:$e")),
                    divider: Icon(Icons.chevron_right),
                    overflow: ScrollableOverflow(
                        controller: _breadCrumbScroller),
                  )),
              Row(
                children: [
                  // IconButton(onPressed: () {}, icon: Icon(Icons.sort)),
                  PopupMenuButton<SortBy>(
                      icon: Icon(Icons.sort),
                      itemBuilder: (context) {
                        return SortBy.values
                            .map((e) =>
                            PopupMenuItem(
                              child:
                              Text(translate(e
                                  .toString()
                                  .split(".")
                                  .last)),
                              value: e,
                            ))
                            .toList();
                      },
                      onSelected: model.changeSortStyle),
                  PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert),
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            child: Row(
                              children: [Icon(Icons.refresh), Text("刷新")],
                            ),
                            value: "refresh",
                          ),
                          PopupMenuItem(
                            child: Row(
                              children: [Icon(Icons.check), Text("多选")],
                            ),
                            value: "select",
                          )
                        ];
                      },
                      onSelected: (v) {
                        if (v == "refresh") {
                          model.refresh();
                        } else if (v == "select") {
                          _selectedItems.clear();
                          model.toggleSelectMode();
                        }
                      }),
                ],
              )
            ],
          ));

  Widget emptyPage() {
    return Column(
      children: [
        headTools(),
        Expanded(child: Center(child: Text("Empty Directory")))
      ],
    );
  }

  Widget listTail() {
    return SizedBox(height: 100);
  }

  Widget? bottomSheet() {
    final state = model.jobState;
    final isOtherPage = _selectedItems.isOtherPage(model.isLocal);
    final selectedItemsLength = "${_selectedItems.length} 个项目";
    final local = _selectedItems.isLocal == null
        ? ""
        : " [${_selectedItems.isLocal! ? '本地' : '远程'}]";

    if (model.selectMode) {
      if (_selectedItems.length == 0 || !isOtherPage) {
        // 选择模式 当前选择页面
        return BottomSheetBody(
            leading: Icon(Icons.check),
            title: "已选择",
            text: selectedItemsLength + local,
            onCanceled: () => model.toggleSelectMode(),
            actions: [
              IconButton(
                icon: Icon(Icons.delete_forever),
                onPressed: () {
                  if(_selectedItems.length>0){
                    model.removeAction(_selectedItems);
                  }
                },
              )
            ]);
      } else {
        // 选择模式 复制目标页面
        return BottomSheetBody(
            leading: Icon(Icons.input),
            title: "粘贴到这里?",
            text: selectedItemsLength + local,
            onCanceled: () => model.toggleSelectMode(),
            actions: [
              IconButton(
                icon: Icon(Icons.paste),
                onPressed: () {
                  model.toggleSelectMode();
                  // TODO
                  model.sendFiles(_selectedItems);
                },
              )
            ]);
      }
    }

    switch (state) {
      case JobState.inProgress:
        return BottomSheetBody(
          leading: CircularProgressIndicator(),
          title: "正在发送文件...",
          text: "速度:  ${(model.jobProgress.speed / 1024).toStringAsFixed(
              2)} kb/s",
          onCanceled: null,
        );
      case JobState.done:
        return BottomSheetBody(
          leading: Icon(Icons.check),
          title: "发送成功!",
          text: "",
          onCanceled: () => model.jobReset(),
        );
      case JobState.error:
        return BottomSheetBody(
          leading: Icon(Icons.error),
          title: "发送错误!",
          text: "",
          onCanceled: () => model.jobReset(),
        );
      case JobState.none:
        break;
    }
    return null;
  }

  List<BreadCrumbItem> getPathBreadCrumbItems(void Function() onHome,
      void Function(String) onPressed) {
    final path = model.currentDir.path;
    final list = Path.split(path);
    list.remove('/');
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
            icon: Icon(Icons.home_filled),
            onPressed: onHome,
          ))
    ];
    breadCrumbList.addAll(list.map((e) =>
        BreadCrumbItem(
            content: TextButton(
                child: Text(e),
                style:
                ButtonStyle(minimumSize: MaterialStateProperty.all(Size(0, 0))),
                onPressed: () => onPressed(e)))));
    return breadCrumbList;
  }
}

class BottomSheetBody extends StatelessWidget {
  BottomSheetBody({required this.leading,
    required this.title,
    required this.text,
    this.onCanceled,
    this.actions});

  final Widget leading;
  final String title;
  final String text;
  final VoidCallback? onCanceled;
  final List<IconButton>? actions;

  @override
  BottomSheet build(BuildContext context) {
    final _actions = actions ?? [];
    return BottomSheet(
      builder: (BuildContext context) {
        return Container(
            height: 65,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: MyTheme.accent50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      leading,
                      SizedBox(width: 16),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 18)),
                          Text(text,
                              style: TextStyle(
                                  fontSize: 14, color: MyTheme.grayBg))
                        ],
                      )
                    ],
                  ),
                  Row(children: () {
                    _actions.add(IconButton(
                      icon: Icon(Icons.cancel_outlined),
                      onPressed: onCanceled,
                    ));
                    return _actions;
                  }())
                ],
              ),
            ));
      },
      onClosing: () {},
      backgroundColor: MyTheme.grayBg,
      enableDrag: false,
    );
  }
}

class SelectedItems {
  bool? _isLocal;
  final List<Entry> _items = [];

  List<Entry> get items => _items;

  int get length => _items.length;

  bool? get isLocal => _isLocal;

  add(bool isLocal, Entry e) {
    if (_isLocal == null) {
      _isLocal = isLocal;
    }
    if (_isLocal != null && _isLocal != isLocal) {
      return;
    }
    if (!_items.contains(e)) {
      _items.add(e);
    }
  }

  bool contains(Entry e) {
    return _items.contains(e);
  }

  remove(Entry e) {
    _items.remove(e);
    if (_items.length == 0) {
      _isLocal = null;
    }
  }

  bool isOtherPage(bool currentIsLocal) {
    if (_isLocal == null) {
      return false;
    } else {
      return _isLocal != currentIsLocal;
    }
  }

  clear() {
    _items.clear();
    _isLocal = null;
  }
}
