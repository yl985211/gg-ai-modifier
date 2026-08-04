/// 主页面 - 底部导航栏

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

class _HomePageState extends ConsumerState<HomePage> {
  static const _channel = MethodChannel('com.yl.aigg/bridge');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
    _getInitialPage();
    // 检查是否有悬浮窗附加的进程
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAttachedProcessOnStartup(ref);
    });
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
    // 每次页面恢复时检查是否有待处理的跳转
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
        // 不切换页面，只确���应用在前台
        break;
      case 'chat':
        ref.read(currentPageProvider.notifier).state = 0;
        break;
      case 'search':
        ref.read(currentPageProvider.notifier).state = 1;
        break;
      case 'script':
        ref.read(currentPageProvider.notifier).state = 2;
        break;
      case 'settings':
        ref.read(currentPageProvider.notifier).state = 3;
        break;
      case 'process':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProcessSelectorPage()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(currentPageProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          ChatPage(),
          const PluginCenterPage(),
          ScriptPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          ref.read(currentPageProvider.notifier).state = index;
        },
        backgroundColor: const Color(0xFFFDFBF7),
        indicatorColor: const Color(0xFF8D6E63).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: Color(0xFF8D6E63)),
            label: 'Chat History',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension),
            selectedIcon: Icon(Icons.extension, color: Color(0xFF8D6E63)),
            label: 'Plugin Center',
          ),
          NavigationDestination(
            icon: Icon(Icons.code),
            selectedIcon: Icon(Icons.code, color: Color(0xFF8D6E63)),
            label: 'Script Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF8D6E63)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
