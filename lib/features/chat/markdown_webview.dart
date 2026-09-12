import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/models/chat_message.dart';

class MarkdownWebView extends StatefulWidget {
  final String? markdownContent;
  final List<ChatMessage>? messages;
  final double maxWidth;
  final VoidCallback? onHeightChanged;

  const MarkdownWebView({
    super.key,
    this.markdownContent,
    this.messages,
    required this.maxWidth,
    this.onHeightChanged,
  }) : assert(markdownContent != null || messages != null);

  @override
  State<MarkdownWebView> createState() => _MarkdownWebViewState();
}

class _MarkdownWebViewState extends State<MarkdownWebView> {
  late final WebViewController _controller;
  double _height = 50;

  @override
  void initState() {
    super.initState();
    final html = widget.messages != null
        ? _buildChatHtml(widget.messages!)
        : _buildSingleHtml(widget.markdownContent!);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF2F3F8))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _measureHeight(),
      ))
      ..loadHtmlString(html);
  }

  void _measureHeight() {
    _doMeasure(0);
  }

  void _doMeasure(int attempt) {
    if (!mounted || attempt > 15) return;
    final delay = attempt == 0 ? 100 : 500;
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted) return;
      _controller
          .runJavaScriptReturningResult('document.body.scrollHeight')
          .then((value) {
        if (!mounted) return;
        final h = (value as num).toDouble();
        if (h > 0 && h != _height) {
          setState(() => _height = h);
          widget.onHeightChanged?.call();
        }
        if (attempt < 5) _doMeasure(attempt + 1);
      }).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.maxWidth,
      height: _height,
      child: WebViewWidget(controller: _controller),
    );
  }

  // ==================== 单内容模式 ====================

  static String _buildSingleHtml(String content) {
    final escaped = _escapeForJs(content);
    return _shell('''
var rawContent = '$escaped';
$_jsCore
(function() {
    var protected = protectLaTeX(rawContent);
    var html = marked.parse(protected);
    html = restoreLaTeX(html);
    document.getElementById('content').innerHTML = html;
    doRender(document.getElementById('content'));
})();''');
  }

  // ==================== 多消息模式 ====================

  static String _buildChatHtml(List<ChatMessage> messages) {
    final htmlBuf = StringBuffer();
    final dataBuf = StringBuffer();
    var aiIdx = 0;

    for (final msg in messages) {
      final time = msg.timestamp.toString().substring(11, 16);
      if (msg.isUser) {
        final safe = msg.content
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('\n', '<br>');
        htmlBuf.write(
          '<div class="msg msg-user">'
          '<div class="msg-header"><span class="msg-sender">我</span>'
          '<span class="msg-time">$time</span></div>'
          '<div class="bubble bubble-user">$safe</div></div>');
      } else {
        htmlBuf.write(
          '<div class="msg msg-ai">'
          '<div class="msg-header"><span class="msg-icon">🤖</span>'
          '<span class="msg-sender">GG-AI</span>'
          '<span class="msg-time">$time</span></div>'
          '<div class="bubble bubble-ai" id="ai$aiIdx"></div></div>');
        dataBuf.write("m[$aiIdx]='${base64Encode(utf8.encode(msg.content))}';");
        aiIdx++;
      }
    }

    return _shell('''
var m={};
$dataBuf
$_jsCore
(function(){
    for(var k in m){
        var el=document.getElementById('ai'+k);
        if(!el) continue;
        var raw=decodeURIComponent(atob(m[k]).split('').map(function(c){return'%'+('00'+c.charCodeAt(0).toString(16)).slice(-2)}).join(''));
        var p=protectLaTeX(raw);
        var h=marked.parse(p);
        h=restoreLaTeX(h);
        el.innerHTML=h;
        doRender(el);
    }
})();''', body: htmlBuf.toString());
  }

  // ==================== 共用部分 ====================

  static String _escapeForJs(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '');

  static String _shell(String script, {String? body}) {
    final b = body ?? '<div id="content"></div>';
    return '<!DOCTYPE html><html><head><meta charset="UTF-8">'
 '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">'
 '<style>'
 '*{margin:0;padding:0;box-sizing:border-box}'
 'body{font-family:-apple-system,sans-serif;font-size:14px;line-height:1.6;color:#213333;background:#F2F3F8;padding:10px;word-wrap:break-word}'
 'h1,h2,h3,h4,h5,h6{color:#304FFE;margin:12px 0 6px;font-weight:600}'
 'h1{font-size:20px}h2{font-size:17px}h3{font-size:15px}'
 'p{margin:6px 0}a{color:#3D5AFE;text-decoration:none}'
 'code{background:#E8EAF6;color:#304FFE;padding:2px 6px;border-radius:4px;font-family:monospace;font-size:13px}'
 'pre{background:#213333;border:1px solid #3D5AFE;border-radius:8px;padding:12px;margin:8px 0;overflow-x:auto}'
 'pre code{background:none;padding:0;color:#F2F3F8}'
 'blockquote{border-left:4px solid #3D5AFE;padding-left:12px;margin:8px 0;color:#4A6572}'
 'ul,ol{margin:6px 0;padding-left:24px}li{margin:3px 0}'
 'table{border-collapse:collapse;width:100%;margin:8px 0}'
 'th,td{border:1px solid #3D5AFE;padding:6px 10px;text-align:left}'
 'th{background:#213333;color:#F2F3F8}'
 'hr{border:none;border-top:1px solid #3D5AFE;margin:12px 0}'
 'strong{color:#213333}em{color:#4A6572}'
 '.mermaid{max-width:100%;max-height:400px;overflow:auto;background:#213333;border-radius:8px;padding:8px;margin:8px 0}'
 '.mermaid svg{max-width:100%;height:auto}'
 '.table-wrapper{overflow-x:auto;max-width:100%}'
 '.msg{margin-bottom:16px}'
 '.msg-header{display:flex;align-items:center;gap:6px;margin-bottom:4px}'
 '.msg-icon{font-size:14px}.msg-sender{font-size:12px;color:#4A6572}.msg-time{font-size:10px;color:#4A6572}'
 '.msg-user .msg-header{justify-content:flex-end}'
 '.bubble{padding:10px 14px;border-radius:12px;max-width:85%;word-break:break-word}'
 '.bubble-user{background:#3D5AFE;border:1px solid #FFFFFF;border-radius:12px;padding:10px 14px;margin-left:auto;color:#FFFFFF}'
 '.bubble-ai{background:#FFFFFF;border:1px solid #3D5AFE;border-radius:12px;padding:10px 14px}'
 '.msg-user .msg-sender{color:#304FFE}.msg-ai .msg-sender{color:#536DFE}'
 '</style>'
 '<link rel="stylesheet" href="file:///android_asset/css/prism-tomorrow.min.css">'
 '<script src="file:///android_asset/js/prism.min.js"></script>'
 '<link rel="stylesheet" href="file:///android_asset/css/katex.min.css">'
 '<script src="file:///android_asset/js/katex.min.js"></script>'
 '<script src="file:///android_asset/js/auto-render.min.js"></script>'
 '<script src="file:///android_asset/js/marked.min.js"></script>'
 '<script src="file:///android_asset/js/mermaid.min.js"></script>'
 '</head><body>$b'
 '<script>$script</script>'
 '</body></html>';
  }

  // JS 核心：marked 配置 + protectLaTeX + restoreLaTeX + renderMermaid + renderKatex
  static const _jsCore = r"""
mermaid.initialize({startOnLoad:false,theme:'dark'});
var renderer=new marked.Renderer();
renderer.code=function(code,lang){
    var t=(typeof code==='object')?code.text:code;
    var l=(typeof code==='object')?code.lang:lang;
    var e=t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    if(l&&typeof Prism!=='undefined'&&Prism.languages[l]){
        try{return '<pre class="language-'+l+'"><code class="language-'+l+'">'+Prism.highlight(t,Prism.languages[l],l)+'</code></pre>'}catch(x){}
    }
    return '<pre class="language-'+(l||'none')+'"><code class="language-'+(l||'none')+'">'+e+'</code></pre>';
};
marked.setOptions({breaks:true,gfm:true,renderer:renderer});
var latexStore=[];
function protectLaTeX(text){
    var cb=[];
    text=text.replace(/(```[\s\S]*?```|`[^`\n]+`)/g,function(m,c){cb.push(c);return'\x00C'+(cb.length-1)+'\x00'});
    text=text.replace(/\$\$([\s\S]*?)\$\$/g,function(m,i){latexStore.push('$$'+i+'$$');return'\x00L'+(latexStore.length-1)+'\x00'});
    text=text.replace(/\$([^\$\n]+?)\$/g,function(m,i){latexStore.push('$'+i+'$');return'\x00L'+(latexStore.length-1)+'\x00'});
    text=text.replace(/\\\[([\s\S]*?)\\\]/g,function(m,i){latexStore.push('$$'+i+'$$');return'\x00L'+(latexStore.length-1)+'\x00'});
    text=text.replace(/\\\((.*?)\\\)/g,function(m,i){latexStore.push('$'+i+'$');return'\x00L'+(latexStore.length-1)+'\x00'});
    text=text.replace(/\x00C(\d+)\x00/g,function(m,i){return cb[parseInt(i)]});
    return text;
}
function restoreLaTeX(html){
    html=html.replace(/\x00L(\d+)\x00/g,function(m,i){
        return '<span class="katex-ph" data-latex="'+latexStore[parseInt(i)].replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;')+'"></span>';
    });
    return html;
}
function renderKatexIn(el){
    el.querySelectorAll('.katex-ph').forEach(function(ph){
        var latex=ph.getAttribute('data-latex');
        try{
            var isD=latex.substring(0,2)==='$$';
            var tex=isD?latex.substring(2,latex.length-2):latex.substring(1,latex.length-1);
            katex.render(tex,ph,{displayMode:isD,throwOnError:false});
        }catch(e){ph.textContent=latex;ph.style.color='#FF5252'}
    });
}
function renderMermaidIn(el){
    el.querySelectorAll('code.language-mermaid').forEach(function(block){
        var pre=block.parentElement;
        var div=document.createElement('div');
        div.className='mermaid';
        div.textContent=block.textContent;
        pre.parentNode.replaceChild(div,pre);
    });
}
function doRender(el){
    renderMermaidIn(el);
    el.querySelectorAll('table').forEach(function(t){
        var w=document.createElement('div');w.className='table-wrapper';
        t.parentNode.insertBefore(w,t);w.appendChild(t);
    });
    renderKatexIn(el);
    if(el.querySelectorAll('.mermaid').length>0){
        if(typeof mermaid.run==='function')mermaid.run().then(function(){window.__done=1}).catch(function(){window.__done=1});
        else if(typeof mermaid.init==='function'){try{mermaid.init(undefined,el.querySelectorAll('.mermaid'))}catch(e){}window.__done=1}
        else window.__done=1;
    }else window.__done=1;
}
""";
}
