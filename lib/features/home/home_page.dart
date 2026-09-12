/// 主页面 - 底部导航栏 + 滑动翻页

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_page.dart';
import '../plugin/plugin_center_page.dart';
import '../script/script_page.dart';
import '../settings/settings_page.dart';
import '../process/process_selector.dart';
import '../../main.dart';

/// 当前选中的页面索引
final currentPageProvider = StateProvider<int>((ref) => 0);

/// 主页面
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with TickerProviderStateMixin {
  static const _channel = MethodChannel('com.yl.aigg/bridge');
  late PageController _pageController;
  bool _isPageChanging = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _channel.setMethodCallHandler(_handleMethodCall);
    _getInitialPage();
    // 检查是否有悬浮窗附加的进程
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAttachedProcessOnStartup(ref);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _getInitialPage() async {
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final page = await _channel.invokeMethod('getInitialPage');
      if (page != null && mounted) {
        _navigateToPage(page as String);
      }
    } catch (_) {}
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNavigate') {
      final page = call.arguments as String?;
      if (page != null && mounted) {
        _navigateToPage(page);
      }
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPendingPage();
  }

  Future<void> _checkPendingPage() async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final page = await _channel.invokeMethod('getInitialPage');
      if (page != null && mounted) {
        _navigateToPage(page as String);
      }
    } catch (_) {}
  }

  void _navigateToPage(String page) {
    switch (page) {
      case 'home':
        break;
      case 'chat':
        _animateToPage(0);
        break;
      case 'search':
        _animateToPage(1);
        break;
      case 'script':
        _animateToPage(2);
        break;
      case 'settings':
        _animateToPage(3);
        break;
      case 'process':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProcessSelectorPage()),
        );
        break;
    }
  }

  void _animateToPage(int index) {
    ref.read(currentPageProvider.notifier).state = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (!_isPageChanging) {
      ref.read(currentPageProvider.notifier).state = index;
    }
  }

  void _onBottomNavTapped(int index) {
    _isPageChanging = true;
    ref.read(currentPageProvider.notifier).state = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    ).then((_) {
      _isPageChanging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(currentPageProvider);

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: const [
          ChatPage(),
          PluginCenterPage(),
          ScriptPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: _onBottomNavTapped,
        backgroundColor: const Color(0xFFF2F3F8),
        indicatorColor: const Color(0xFF3D5AFE).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: Color(0xFF3D5AFE)),
            label: '对话记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension),
            selectedIcon: Icon(Icons.extension, color: Color(0xFF3D5AFE)),
            label: '插件中心',
          ),
          NavigationDestination(
            icon: Icon(Icons.code),
            selectedIcon: Icon(Icons.code, color: Color(0xFF3D5AFE)),
            label: '脚本库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF3D5AFE)),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
