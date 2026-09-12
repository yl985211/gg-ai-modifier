package com.yl.aigg.ai_gg666

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.widget.ImageView
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class OverlayService : Service() {

    companion object {
        private const val CHANNEL_ID = "overlay_channel"
        private const val NOTIFICATION_ID = 1
        var isRunning = false
    }

    private var wm: WindowManager? = null
    private var ballView: View? = null
    private var ballParams: WindowManager.LayoutParams? = null
    private var panel: View? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private val handler = Handler(Looper.getMainLooper())

    // 搜索状态
    private var searchResults: List<Map<String, Any>> = emptyList()
    private var searchDataType = "dword"
    private val selectedIndices = mutableSetOf<Int>() // 选中的结果索引
    // 搜索输入框的值（保持不丢失）
    private var savedSearchInput = ""
    private var savedFilterInput = ""
    private var savedRangeMin = ""
    private var savedRangeMax = ""
    private var savedScrollY = 0

    // AI 对话历史（持久化在内存中，防止切换后消失）
    private val chatMessages = mutableListOf<Pair<String, String>>() // (sender, message)
    private var isAiResponding = false

    // 记住上次打开的面板
    private var lastPanel = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        createBall()
        // 恢复上次打开的面板
        lastPanel = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE).getString("last_panel", "") ?: ""
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY

    override fun onDestroy() {
        isRunning = false
        removeBall()
        super.onDestroy()
    }

    // ==================== 通知 ====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "GG-AI 悬浮窗", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID).setContentTitle("GG-AI").setContentText("悬浮窗运行中")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi).build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setContentTitle("GG-AI").setContentText("悬浮窗运行中")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pi).build()
        }
    }

    // ==================== 悬浮球 ====================

    private fun createBall() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        ballView = ImageView(this).apply {
            setImageResource(R.drawable.xfc)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.parseColor("#f6f2c1")) }
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        
        ballParams = WindowManager.LayoutParams(
            dp(50), 
            dp(50), 
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or 
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply { 
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = dp(200)
        }

        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f; var dragging = false
        ballView?.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { ix = ballParams?.x ?: 0; iy = ballParams?.y ?: 0; tx = e.rawX; ty = e.rawY; dragging = false; true }
                MotionEvent.ACTION_MOVE -> {
                    if (kotlin.math.abs(e.rawX - tx) > 10 || kotlin.math.abs(e.rawY - ty) > 10) dragging = true
                    ballParams?.x = ix + (e.rawX - tx).toInt(); ballParams?.y = iy + (e.rawY - ty).toInt()
                    try { wm?.updateViewLayout(ballView, ballParams) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> { if (!dragging) showLastOrMainMenu(); true }
                else -> false
            }
        }
        try { wm?.addView(ballView, ballParams) } catch (_: Exception) {}
    }

    private fun removeBall() {
        closePanel()
        try { ballView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        ballView = null
    }

    // ==================== 面板管理 ====================

    private fun saveLastPanel(name: String) {
        lastPanel = name
        getSharedPreferences("gg_overlay", Context.MODE_PRIVATE).edit().putString("last_panel", name).apply()
    }

    private fun closePanel() {
        // 关闭前保存滚动位置（仅当面板有 ScrollView 时才更新，避免菜单面板覆盖搜索面板的滚动位置）
        try {
            fun findScrollView(v: android.view.View): android.widget.ScrollView? {
                if (v is android.widget.ScrollView) return v
                if (v is android.view.ViewGroup) {
                    for (i in 0 until v.childCount) {
                        val found = findScrollView(v.getChildAt(i))
                        if (found != null) return found
                    }
                }
                return null
            }
            panel?.let { findScrollView(it)?.let { sv -> if (sv.scrollY > 0) savedScrollY = sv.scrollY } }
        } catch (_: Exception) {}
        try { panel?.let { wm?.removeView(it) } } catch (_: Exception) {}
        panel = null; panelParams = null
    }

    private fun showPanel(view: View, w: Int = 280, h: Int = 400) {
        closePanel()
        val dm = resources.displayMetrics
        val screenW = dm.widthPixels
        val screenH = dm.heightPixels
        val panelW = dp(w).coerceAtMost(screenW - dp(20))
        val panelH = dp(h).coerceAtMost(screenH - dp(20))
        
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        
        panelParams = WindowManager.LayoutParams(
            panelW,
            panelH,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (screenW - panelW) / 2
            y = (screenH - panelH) / 2
        }
        panel = view
        try { wm?.addView(panel, panelParams) } catch (_: Exception) {}
    }
    
    // 创建可获得焦点的面板（用于输入法）
    private fun showFocusablePanel(view: View, w: Int = 280, h: Int = 400) {
        closePanel()
        val dm = resources.displayMetrics
        val screenW = dm.widthPixels
        val screenH = dm.heightPixels
        val panelW = dp(w).coerceAtMost(screenW - dp(20))
        val panelH = dp(h).coerceAtMost(screenH - dp(20))
        
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        
        panelParams = WindowManager.LayoutParams(
            panelW,
            panelH,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (screenW - panelW) / 2
            y = (screenH - panelH) / 2
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
        }
        panel = view
        try { wm?.addView(panel, panelParams) } catch (_: Exception) {}
    }

    private fun overlayType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
    }

    // ==================== 可拖动面板包装 ====================

    private fun makeDraggablePanel(title: String, contentBuilder: (LinearLayout) -> Unit, w: Int = 280, h: Int = 400, onBack: (() -> Unit)? = null, titleIcon: Int? = null, bgColor: String = "#F2F3F8") {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat(); setColor(Color.parseColor(bgColor)); setStroke(1, Color.parseColor("#3D5AFE"))
            }
        }

        // 可拖动标题栏
        val titleBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            minimumHeight = 0
            setPadding(dp(5), dp(5), dp(5), dp(5))
            setBackgroundColor(Color.parseColor(bgColor))
        }
        if (titleIcon != null) {
            titleBar.addView(ImageView(this).apply {
                setImageResource(titleIcon)
                layoutParams = LinearLayout.LayoutParams(dp(18), dp(18)).apply { marginEnd = dp(6) }
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            })
        }
        val titleText = TextView(this).apply {
            text = title; setTextColor(Color.parseColor("#F2F3F8")); textSize = 13f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        titleBar.addView(titleText)

        // 返回按钮（如果不是主菜单）
        if (title != "🎮 GG-AI Modifier") {
            titleBar.addView(TextView(this).apply {
                text = "返回"; setTextColor(Color.parseColor("#FFFFFF")); textSize = 12f
                background = GradientDrawable().apply { cornerRadius = dp(4).toFloat(); setColor(Color.parseColor("#3D5AFE")) }
                setPadding(dp(5), dp(5), dp(5), dp(5))
                setOnClickListener { onBack?.invoke() ?: showMainMenu() }
            })
        }

        root.addView(titleBar)

        // 分割线
        root.addView(View(this).apply {
            setBackgroundColor(Color.parseColor("#E8EAF6"))
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1))
        })

        // 内容区域
        val contentArea = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        }
        contentBuilder(contentArea)
        root.addView(contentArea)

        // 标题栏拖动支持 - 修复横屏模式下的拖动问题
        var pix = 0; var piy = 0; var ptx = 0f; var pty = 0f; var isDragging = false
        val dm = resources.displayMetrics
        
        titleBar.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    pix = panelParams?.x ?: 0
                    piy = panelParams?.y ?: 0
                    ptx = e.rawX
                    pty = e.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    isDragging = true
                    val dx = (e.rawX - ptx).toInt()
                    val dy = (e.rawY - pty).toInt()
                    
                    // 计算新位置，确保不超出屏幕边界
                    val screenW = dm.widthPixels
                    val screenH = dm.heightPixels
                    val panelW = panelParams?.width ?: 0
                    val panelH = panelParams?.height ?: 0
                    
                    var newX = pix + dx
                    var newY = piy + dy
                    
                    // 限制在屏幕范围内
                    newX = newX.coerceIn(-panelW / 2, screenW - panelW / 2)
                    newY = newY.coerceIn(0, screenH - panelH)
                    
                    panelParams?.x = newX
                    panelParams?.y = newY
                    try { wm?.updateViewLayout(panel, panelParams) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    isDragging
                }
                else -> false
            }
        }

        // 根据面板类型选择显示方式
        if (title == "🤖 AI 对话") {
            showFocusablePanel(root, w, h)
        } else {
            showPanel(root, w, h)
        }
    }

    // ==================== 主菜单 ====================

    private fun showLastOrMainMenu() {
        when (lastPanel) {
            "process" -> showProcessPanel()
            "search" -> showSearchPanel()
            "chat" -> showAIChatPanel()
            "script" -> showScriptPanel()
            else -> showMainMenu()
        }
    }

    private fun showMainMenu() {
        saveLastPanel("menu")
        makeDraggablePanel("GG-AI Modifier", { content ->
            val sv = ScrollView(this).apply {
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            }
            val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(8), dp(12), dp(8)) }

            list.addView(menuBtn("附加进程", R.drawable.jingcheng) { showProcessPanel() })
            list.addView(menuBtn("内存搜索", R.drawable.neichun) { showSearchPanel() })
            list.addView(menuBtn("AI 对话", R.drawable.ai) { showAIChatPanel() })
            list.addView(menuBtn("脚本库", R.drawable.jiaoben) { showScriptPanel() })

            sv.addView(list); content.addView(sv)

            // 底部按钮
            val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(8), dp(12), dp(8)) }
            bar.addView(iconBtn(R.drawable.gb_xfc, "悬浮窗") { stopSelf() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            bar.addView(iconBtn(R.drawable.ck_gb, "菜单") { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(bar)
        }, 250, 380, titleIcon = R.drawable.xfc, bgColor = "#536DFE")
    }

    // ==================== 进程面板 ====================

    private fun showProcessPanel() {
        saveLastPanel("process")
        makeDraggablePanel("选择游戏进程", { content ->
            val status = TextView(this).apply { text = "正在扫描..."; setTextColor(Color.parseColor("#F2F3F8")); textSize = 12f; setPadding(dp(12), dp(8), dp(12), dp(4)) }
            content.addView(status)

            val sv = ScrollView(this).apply { layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f) }
            val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(8), dp(4), dp(8), dp(4)) }
            sv.addView(list); content.addView(sv)

            // 底部按钮
            val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(4), dp(12), dp(8)) }
            bar.addView(iconBtn(R.drawable.shuaxing) { loadProcs(list, status) }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            bar.addView(iconBtn(R.drawable.ck_gb) { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(bar)

            loadProcs(list, status)
        }, 300, 450, titleIcon = R.drawable.jingcheng, bgColor = "#213333")
    }

    private fun loadProcs(list: LinearLayout, status: TextView) {
        status.text = "正在扫描..."; list.removeAllViews()
        Thread {
            val procs = ProcessManager.getProcessList(this@OverlayService).filter {
                val p = it["packageName"] as String
                p.isNotEmpty() && p.contains(".") && !p.startsWith("com.android.") && !p.startsWith("android.") &&
                        p != "system" && p != "zygote" && p != "zygote64"
            }
            handler.post {
                status.text = "找到 ${procs.size} 个应用"
                for (proc in procs) {
                    val name = proc["processName"] as String; val pkg = proc["packageName"] as String; val pid = proc["pid"] as Int
                    val item = LinearLayout(this).apply {
                        orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(10), dp(12), dp(10))
                        background = GradientDrawable().apply { cornerRadius = dp(8).toFloat(); setColor(Color.parseColor("#304FFE")) }
                        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(4) }
                    }
                    item.addView(TextView(this).apply { text = name; setTextColor(Color.parseColor("#F2F3F8")); textSize = 14f })
                    item.addView(TextView(this).apply { text = "$pkg | PID: $pid"; setTextColor(Color.parseColor("#000000")); textSize = 11f })
                    item.setOnClickListener {
                        Thread {
                            val ok = MemoryEngine.attachProcess(pid)
                            handler.post {
                                status.text = if (ok) "✅ 已附加: $name" else "❌ 附加失败"
                                // 附加成功后，通知主应用更新状态，并重置搜索结果
                                if (ok) {
                                    saveAttachedProcess(pid, pkg, name)
                                    searchResults = emptyList()
                                }
                            }
                        }.start()
                    }
                    list.addView(item)
                }
            }
        }.start()
    }
    
    // 保存附加的进程信息，供主应用读取
    private fun saveAttachedProcess(pid: Int, packageName: String, processName: String) {
        try {
            val prefs = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE)
            prefs.edit().apply {
                putInt("attached_pid", pid)
                putString("attached_package", packageName)
                putString("attached_name", processName)
                putLong("attached_time", System.currentTimeMillis())
                apply()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ==================== 搜索面板 ====================

    private var currentSearchMode = "exact"

    private fun showSearchPanel() {
        saveLastPanel("search")
        val dm = resources.displayMetrics
        val screenW = dm.widthPixels
        val screenH = dm.heightPixels
        val density = dm.density
        val isLandscape = screenW > screenH

        // 横屏：宽度88%屏幕，高度93%屏幕；竖屏：保持原样
        val panelWDp = if (isLandscape) ((screenW * 0.88f) / density).toInt().coerceIn(650, 900) else 320
        val panelHDp = if (isLandscape) ((screenH * 0.93f) / density).toInt().coerceIn(380, 550) else 520

        makeDraggablePanel("内存搜索", { content ->
            val pid = MemoryEngine.getAttachedPid()

            if (isLandscape) {
                // ========== 横屏模式：左右两栏布局 ==========
                val mainRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
                }

                // ---- 左栏：搜索控件 ----
                val leftPanel = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
                    setPadding(dp(8), dp(4), dp(4), dp(4))
                }

                // 状态行
                val status = TextView(this).apply {
                    text = if (pid != null) "PID:$pid" else "⚠未附加"
                    setTextColor(if (pid != null) Color.parseColor("#66BB6A") else Color.parseColor("#FF8F00"))
                    textSize = 11f
                }
                leftPanel.addView(status)

                // 类型选择
                val types = arrayOf("dword", "float", "double", "byte", "word", "qword")
                val typeSpinner = Spinner(this).apply {
                    adapter = ArrayAdapter(this@OverlayService, android.R.layout.simple_spinner_dropdown_item, types)
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                }
                leftPanel.addView(typeSpinner)

                // 模式切换按钮
                val modeRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(4), 0, dp(4)) }
                fun modeBtn(label: String, mode: String): Button {
                    return Button(this).apply {
                        text = label; textSize = 10f; setTextColor(Color.parseColor("#F2F3F8"))
                        background = GradientDrawable().apply {
                            cornerRadius = dp(4).toFloat()
                            setColor(if (currentSearchMode == mode) Color.parseColor("#3D5AFE") else Color.parseColor("#333333"))
                        }
                        setPadding(dp(4), dp(2), dp(4), dp(2))
                        layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(2) }
                        setOnClickListener { currentSearchMode = mode; showSearchPanel() }
                    }
                }
                modeRow.addView(modeBtn("精确", "exact"))
                modeRow.addView(modeBtn("模糊", "fuzzy"))
                modeRow.addView(modeBtn("范围", "range"))
                modeRow.addView(modeBtn("地址", "addr"))
                modeRow.addView(modeBtn("机器码", "machine"))
                leftPanel.addView(modeRow)

                // 分割线
                leftPanel.addView(View(this).apply {
                    setBackgroundColor(Color.parseColor("#E8EAF6"))
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply { topMargin = dp(4); bottomMargin = dp(4) }
                })

                // 输入区域（根据模式）
                buildSearchInputArea(leftPanel, status, typeSpinner, null, dp(4))

                // 弹性空间
                leftPanel.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
                })

                // 底部按钮
                val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(4), 0, 0) }
                bar.addView(iconBtn(R.drawable.shuaxing) {
                    searchResults = emptyList(); selectedIndices.clear(); status.text = "已重置"
                    val resultList = leftPanel.tag as? LinearLayout
                    resultList?.removeAllViews()
                    resultList?.addView(TextView(this@OverlayService).apply {
                        text = "暂无结果"; setTextColor(Color.parseColor("#3D5AFE")); textSize = 12f
                        setPadding(dp(8), dp(20), dp(8), dp(8)); gravity = Gravity.CENTER
                    })
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                bar.addView(iconBtn(R.drawable.ck_gb) { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                leftPanel.addView(bar)

                mainRow.addView(leftPanel)

                // 分割线（竖向）
                mainRow.addView(View(this).apply {
                    setBackgroundColor(Color.parseColor("#E8EAF6"))
                    layoutParams = LinearLayout.LayoutParams(dp(1), LinearLayout.LayoutParams.MATCH_PARENT)
                })

                // ---- 右栏：搜索结果 ----
                val rightPanel = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
                    setPadding(dp(4), dp(4), dp(8), dp(4))
                }

                val resultTitle = TextView(this).apply {
                    text = "搜索结果"; setTextColor(Color.parseColor("#4A6572")); textSize = 11f
                    setPadding(0, 0, 0, dp(4))
                }
                rightPanel.addView(resultTitle)

                // 固定操作栏容器
                val actionBarContainer = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                }
                rightPanel.addView(actionBarContainer)

                val rsv = ScrollView(this).apply {
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
                }
                val rl = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, 0, 0, 0) }
                rsv.addView(rl)

                if (searchResults.isNotEmpty()) {
                    status.text = "${searchResults.size}个结果"
                    updateSearchResults(rl, searchResults, actionBarContainer)
                } else {
                    rl.addView(TextView(this).apply {
                        text = "暂无结果"; setTextColor(Color.parseColor("#3D5AFE")); textSize = 12f
                        setPadding(dp(8), dp(20), dp(8), dp(8)); gravity = Gravity.CENTER
                    })
                }

                rightPanel.addView(rsv)
                // 恢复滚动位置
                if (savedScrollY > 0) {
                    rsv.post { rsv.scrollY = savedScrollY; savedScrollY = 0 }
                }
                mainRow.addView(rightPanel)

                content.addView(mainRow)

                // 保存 rl 引用供回调使用（横屏模式下需要设置到 leftPanel.tag）
                content.tag = rl
                leftPanel.tag = rl
            } else {
                // ========== 竖屏模式：原有上下布局 ==========
                val topRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(8), dp(4), dp(8), dp(2))
                }
                val status = TextView(this).apply {
                    text = if (pid != null) "PID:$pid" else "⚠未附加"
                    setTextColor(if (pid != null) Color.parseColor("#66BB6A") else Color.parseColor("#FF8F00"))
                    textSize = 11f
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
                topRow.addView(status)

                val types = arrayOf("dword", "float", "double", "byte", "word", "qword")
                val typeSpinner = Spinner(this).apply {
                    adapter = ArrayAdapter(this@OverlayService, android.R.layout.simple_spinner_dropdown_item, types)
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                }
                topRow.addView(typeSpinner)
                content.addView(topRow)

                val modeRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(6), dp(2), dp(6), dp(2)) }
                fun modeBtn(label: String, mode: String): Button {
                    return Button(this).apply {
                        text = label; textSize = 10f; setTextColor(Color.parseColor("#F2F3F8"))
                        background = GradientDrawable().apply {
                            cornerRadius = dp(4).toFloat()
                            setColor(if (currentSearchMode == mode) Color.parseColor("#3D5AFE") else Color.parseColor("#333333"))
                        }
                        setPadding(dp(4), dp(2), dp(4), dp(2))
                        layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(2) }
                        setOnClickListener { currentSearchMode = mode; showSearchPanel() }
                    }
                }
                modeRow.addView(modeBtn("精确", "exact"))
                modeRow.addView(modeBtn("模糊", "fuzzy"))
                modeRow.addView(modeBtn("范围", "range"))
                modeRow.addView(modeBtn("地址", "addr"))
                modeRow.addView(modeBtn("机器码", "machine"))
                content.addView(modeRow)

                // 输入区域（在结果列表上面）
                buildSearchInputArea(content, status, typeSpinner, null, dp(12))

                // 固定操作栏容器
                val actionBarContainer = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                }
                content.addView(actionBarContainer)

                // 结果列表
                val rsv = ScrollView(this).apply { layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f) }
                val rl = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(6), dp(2), dp(6), dp(2)) }
                rsv.addView(rl)
                // 保存 rl 引用供回调使用
                content.tag = rl
                if (searchResults.isNotEmpty()) {
                    status.text = "${searchResults.size}个结果"
                    updateSearchResults(rl, searchResults, actionBarContainer)
                }
                content.addView(rsv)
                // 恢复滚动位置
                if (savedScrollY > 0) {
                    rsv.post { rsv.scrollY = savedScrollY; savedScrollY = 0 }
                }

                val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(8), dp(2), dp(8), dp(4)) }
                bar.addView(iconBtn(R.drawable.shuaxing) {
                    searchResults = emptyList(); selectedIndices.clear(); status.text = "已重置"
                    rl.removeAllViews()
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                bar.addView(iconBtn(R.drawable.ck_gb) { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                content.addView(bar)
            }
        }, panelWDp, panelHDp, titleIcon = R.drawable.neichun, bgColor = "#213333")
    }

    // 构建搜索输入区域（横屏/竖屏复用）
    private fun buildSearchInputArea(parent: LinearLayout, status: TextView, typeSpinner: Spinner, rl: LinearLayout?, inputPadding: Int) {
        // 获取结果列表容器：优先使用传入的 rl，否则从 parent.tag 获取
        fun getResultList(): LinearLayout? = rl ?: (parent.tag as? LinearLayout)

        when (currentSearchMode) {
            "exact" -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                val inp = EditText(this).apply {
                    hint = "输入数值"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedSearchInput)
                }
                row.addView(inp)
                row.addView(iconBtn(R.drawable.bt_shuousuo) {
                    val v = inp.text.toString()
                    if (v.isEmpty()) { status.text = "❌请输入数值"; return@iconBtn }
                    savedSearchInput = v
                    if (MemoryEngine.getAttachedPid() == null) { status.text = "❌请先附加"; return@iconBtn }
                    val dtype = typeSpinner.selectedItem.toString(); searchDataType = dtype
                    status.text = "搜索中..."
                    val resultList = getResultList()
                    resultList?.removeAllViews(); searchResults = emptyList()
                    Thread {
                        val t = System.currentTimeMillis()
                        val nv: Any = if (dtype == "float" || dtype == "double") v.toDoubleOrNull() ?: 0.0 else v.toLongOrNull() ?: 0
                        val res = MemoryEngine.searchExact(nv, dtype)
                        searchResults = res
                        notifySearchComplete(res.size, t)
                    }.start()
                })
                parent.addView(row)

                val fRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                val fInp = EditText(this).apply {
                    hint = "新值(过滤)"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedFilterInput)
                }
                fRow.addView(fInp)
                fRow.addView(iconBtn(R.drawable.bt_guolv) {
                    val v = fInp.text.toString()
                    if (v.isEmpty() || searchResults.isEmpty()) { status.text = "❌请先搜索"; return@iconBtn }
                    savedFilterInput = v
                    status.text = "过滤中..."
                    val resultList = getResultList()
                    Thread {
                        val t = System.currentTimeMillis()
                        val nv: Any = if (searchDataType == "float" || searchDataType == "double") v.toDoubleOrNull() ?: 0.0 else v.toLongOrNull() ?: 0
                        val res = MemoryEngine.filterResults(searchResults.mapNotNull { (it["addressInt"] as? Number)?.toLong() }, nv, searchDataType)
                        searchResults = res
                        notifySearchComplete(res.size, t)
                    }.start()
                })
                parent.addView(fRow)
            }
            "fuzzy" -> {
                val grid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                fun fuzzyBtn(label: String, cmp: String, color: String): Button {
                    return Button(this).apply {
                        text = label; textSize = 11f; setTextColor(Color.parseColor("#F2F3F8"))
                        background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor(color)) }
                        setPadding(dp(8), dp(4), dp(8), dp(4))
                        layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(3); bottomMargin = dp(2) }
                        setOnClickListener {
                            if (MemoryEngine.getAttachedPid() == null) { status.text = "❌请先附加"; return@setOnClickListener }
                            val dtype = typeSpinner.selectedItem.toString(); searchDataType = dtype
                            status.text = "模糊搜索..."
                            Thread {
                                try {
                                    val t = System.currentTimeMillis()
                                    val res = MemoryEngine.searchFuzzy(cmp, dtype)
                                    searchResults = res
                                    notifySearchComplete(res.size, t)
                                } catch (_: Exception) {}
                            }.start()
                        }
                    }
                }
                val r1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                r1.addView(fuzzyBtn("变大", "increased", "#E53935"))
                r1.addView(fuzzyBtn("变小", "decreased", "#43A047"))
                r1.addView(fuzzyBtn("没变", "unchanged", "#1E88E5"))
                r1.addView(fuzzyBtn("改变", "changed", "#FB8C00"))
                grid.addView(r1)
                parent.addView(grid)
            }
            "range" -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                val minInp = EditText(this).apply {
                    hint = "Min"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedRangeMin)
                }
                val maxInp = EditText(this).apply {
                    hint = "Max"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedRangeMax)
                }
                row.addView(minInp)
                row.addView(TextView(this).apply { text = "~"; setTextColor(Color.parseColor("#F2F3F8")); setPadding(dp(4), dp(6), dp(4), dp(6)) })
                row.addView(maxInp)
                row.addView(smallBtn("扫描") {
                    val lo = minInp.text.toString().toLongOrNull()
                    val hi = maxInp.text.toString().toLongOrNull()
                    if (lo == null || hi == null) { status.text = "❌输入范围"; return@smallBtn }
                    savedRangeMin = minInp.text.toString()
                    savedRangeMax = maxInp.text.toString()
                    if (MemoryEngine.getAttachedPid() == null) { status.text = "❌请先附加"; return@smallBtn }
                    val dtype = typeSpinner.selectedItem.toString(); searchDataType = dtype
                    status.text = "范围扫描..."
                    val resultList = getResultList()
                    resultList?.removeAllViews(); searchResults = emptyList()
                    Thread {
                        val t = System.currentTimeMillis()
                        val res = MemoryEngine.searchByRange(lo, hi, dtype)
                        searchResults = res
                        notifySearchComplete(res.size, t)
                    }.start()
                })
                parent.addView(row)
            }
            "addr" -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                val inp = EditText(this).apply {
                    hint = "0x728B3A4D"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_TEXT
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedSearchInput)
                }
                row.addView(inp)
                row.addView(smallBtn("读取") {
                    val addr = inp.text.toString().trim()
                    if (addr.isEmpty()) { status.text = "❌输入地址"; return@smallBtn }
                    savedSearchInput = addr
                    if (MemoryEngine.getAttachedPid() == null) { status.text = "❌请先附加"; return@smallBtn }
                    searchDataType = "addr"
                    status.text = "读取中..."
                    val resultList = getResultList()
                    resultList?.removeAllViews(); searchResults = emptyList()
                    Thread {
                        val t = System.currentTimeMillis()
                        val res = MemoryEngine.searchAob(addr)
                        searchResults = res
                        notifySearchComplete(res.size, t)
                    }.start()
                })
                parent.addView(row)
            }
            "machine" -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(inputPadding, dp(2), inputPadding, dp(2)) }
                val inp = EditText(this).apply {
                    hint = "48 89 5C 24 ?? CC"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#304FFE")) }
                    setPadding(dp(8), dp(6), dp(8), dp(6)); textSize = 13f
                    inputType = android.text.InputType.TYPE_CLASS_TEXT
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setText(savedSearchInput)
                }
                row.addView(inp)
                row.addView(iconBtn(R.drawable.bt_shuousuo) {
                    val pattern = inp.text.toString().trim()
                    if (pattern.isEmpty()) { status.text = "❌输入机器码"; return@iconBtn }
                    savedSearchInput = pattern
                    if (MemoryEngine.getAttachedPid() == null) { status.text = "❌请先附加"; return@iconBtn }
                    searchDataType = "aob"
                    status.text = "扫描中..."
                    val resultList = getResultList()
                    resultList?.removeAllViews(); searchResults = emptyList()
                    Thread {
                        val t = System.currentTimeMillis()
                        val res = MemoryEngine.searchAob(pattern)
                        searchResults = res
                        notifySearchComplete(res.size, t)
                    }.start()
                })
                parent.addView(row)
            }
        }
    }
    
    // 搜索完成通知：尝试更新当前面板UI，若面板已关闭则等重新打开时自动显示结果
    private fun notifySearchComplete(count: Int, startTime: Long) {
        val elapsed = String.format("%.2f", (System.currentTimeMillis() - startTime) / 1000.0)
        try {
            handler.post {
                try {
                    // 尝试更新当前面板的UI
                    refreshCurrentPanel()
                    Toast.makeText(this, "${count}个结果 ${elapsed}s", Toast.LENGTH_SHORT).show()
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    // 刷新当前搜索面板的结果显示
    private fun refreshCurrentPanel() {
        val content = panel as? android.view.ViewGroup ?: return
        // 找到 ScrollView 中的 rl（结果列表容器）
        fun findResultList(v: android.view.ViewGroup): LinearLayout? {
            for (i in 0 until v.childCount) {
                val child = v.getChildAt(i)
                if (child is android.widget.ScrollView) {
                    val inner = child.getChildAt(0)
                    if (inner is LinearLayout) return inner
                }
                if (child is android.view.ViewGroup) {
                    val found = findResultList(child)
                    if (found != null) return found
                }
            }
            return null
        }
        // 找到操作栏容器
        fun findActionBarContainer(v: android.view.ViewGroup): LinearLayout? {
            for (i in 0 until v.childCount) {
                val child = v.getChildAt(i)
                if (child is LinearLayout && child.childCount > 0) {
                    val firstChild = child.getChildAt(0)
                    if (firstChild is Button && (firstChild.text?.toString()?.contains("全") == true)) {
                        return child
                    }
                }
                if (child is android.view.ViewGroup) {
                    val found = findActionBarContainer(child)
                    if (found != null) return found
                }
            }
            return null
        }
        val rl = findResultList(content) ?: return
        val abc = findActionBarContainer(content)
        if (searchResults.isNotEmpty()) {
            updateSearchResults(rl, searchResults, abc)
        }
    }

    private fun updateSearchResults(rl: LinearLayout, results: List<Map<String, Any>>, actionBarContainer: LinearLayout? = null) {
        rl.removeAllViews()
        actionBarContainer?.removeAllViews()
        selectedIndices.clear()

        if (results.isEmpty()) {
            if (actionBarContainer != null) {
                actionBarContainer.visibility = android.view.View.GONE
            }
            rl.addView(TextView(this).apply { text = "未找到结果"; setTextColor(Color.parseColor("#4A6572")); textSize = 11f; setPadding(dp(8), dp(4), dp(8), dp(4)) })
            return
        }

        // 批量操作按钮栏
        val actionBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(2), dp(2), dp(2), dp(4))
            background = GradientDrawable().apply { cornerRadius = dp(4).toFloat(); setColor(Color.parseColor("#213333")) }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(4) }
        }

        // 实际显示的结果数量（最多100）
        val displayCount = minOf(results.size, 300)

        // 创建均匀分布的按钮
        fun actionBtn(text: String, onClick: () -> Unit): Button {
            return Button(this).apply {
                this.text = text; setTextColor(Color.parseColor("#F2F3F8")); textSize = 11f
                background = GradientDrawable().apply { cornerRadius = dp(4).toFloat(); setColor(Color.parseColor("#3D5AFE")) }
                setPadding(dp(4), dp(0), dp(4), dp(0))
                layoutParams = LinearLayout.LayoutParams(0, dp(30), 1f).apply { marginEnd = dp(2) }
                setOnClickListener { onClick() }
            }
        }

        // 全选/取消全选
        actionBar.addView(actionBtn("☑全") {
            if (selectedIndices.size >= displayCount) {
                selectedIndices.clear()
            } else {
                selectedIndices.clear()
                for (i in 0 until displayCount) {
                    selectedIndices.add(i)
                }
            }
            updateSearchResults(rl, results, actionBarContainer)
        })

        // 复制地址
        actionBar.addView(actionBtn("📋址") {
            if (selectedIndices.isEmpty()) { Toast.makeText(this, "请先勾选", Toast.LENGTH_SHORT).show(); return@actionBtn }
            val addrs = selectedIndices.map { results[it]["address"] as String }.joinToString("\n")
            copyToClipboard(addrs)
            Toast.makeText(this, "已复制${selectedIndices.size}个地址", Toast.LENGTH_SHORT).show()
        })

        // 复制机器码
        actionBar.addView(actionBtn("📋码") {
            if (selectedIndices.isEmpty()) { Toast.makeText(this, "请先勾选", Toast.LENGTH_SHORT).show(); return@actionBtn }
            val codes = selectedIndices.map { results[it]["machineCode"] as? String ?: "" }.joinToString("\n")
            copyToClipboard(codes)
            Toast.makeText(this, "已复制${selectedIndices.size}条机器码", Toast.LENGTH_SHORT).show()
        })

        // 复制值
        actionBar.addView(actionBtn("📋值") {
            if (selectedIndices.isEmpty()) { Toast.makeText(this, "请先勾选", Toast.LENGTH_SHORT).show(); return@actionBtn }
            val vals = selectedIndices.map { "${results[it]["value"]}" }.joinToString("\n")
            copyToClipboard(vals)
            Toast.makeText(this, "已复制${selectedIndices.size}个值", Toast.LENGTH_SHORT).show()
        })

        // 添加到AI对话
        actionBar.addView(actionBtn("🤖") {
            if (selectedIndices.isEmpty()) { Toast.makeText(this, "请先勾选", Toast.LENGTH_SHORT).show(); return@actionBtn }
            val selectedResults = selectedIndices.map { results[it] }
            addResultsToAIChat(selectedResults)
            Toast.makeText(this, "已添加${selectedIndices.size}条到AI", Toast.LENGTH_SHORT).show()
        })

        // 编辑选中项（支持单条和多条）
        actionBar.addView(actionBtn("✏️") {
            if (selectedIndices.isEmpty()) { Toast.makeText(this, "请先勾选", Toast.LENGTH_SHORT).show(); return@actionBtn }
            val selectedResults = selectedIndices.map { results[it] }
            showBatchEditDialog(selectedResults)
        })

        if (actionBarContainer != null) {
            actionBarContainer.addView(actionBar)
            actionBarContainer.visibility = android.view.View.VISIBLE
        } else {
            rl.addView(actionBar)
        }

        // 结果列表（最多显示100条）
        for (index in 0 until displayCount) {
            val r = results[index]
            val addr = r["address"] as String
            val v = r["value"]
            val mc = r["machineCode"] as? String ?: ""
            val displayText = if (mc.isNotEmpty()) "${index+1}. $mc=$v" else "${index+1}. $addr=$v"
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL; setPadding(dp(4), dp(3), dp(4), dp(3))
                background = GradientDrawable().apply { cornerRadius = dp(4).toFloat(); setColor(Color.parseColor("#304FFE")) }
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(2) }
            }

            // 复选框
            val checkBox = android.widget.CheckBox(this).apply {
                isChecked = selectedIndices.contains(index)
                buttonTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#3D5AFE"))
                setPadding(0, 0, dp(4), 0)
                setOnCheckedChangeListener { _, isChecked ->
                    if (isChecked) selectedIndices.add(index) else selectedIndices.remove(index)
                }
            }
            row.addView(checkBox)

            // 机器码+值（或地址+值作为fallback）
            row.addView(TextView(this).apply {
                text = displayText; setTextColor(Color.parseColor("#3D5AFE")); textSize = 10f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })

            // 单个操作按钮
            row.addView(miniBtn("改") {
                // 保存滚动位置
                val sv = rl.parent as? android.widget.ScrollView
                savedScrollY = sv?.scrollY ?: 0
                showWriteDialog(addr, v, mc)
            })
            row.addView(miniBtn("冻") {
                val ai = addr.removePrefix("0x").removePrefix("0X").toLongOrNull(16)?.toInt() ?: return@miniBtn
                Thread { if (v != null) MemoryFreezer.freeze(ai, v, searchDataType) }.start()
            })

            rl.addView(row)
        }
    }

    // 复制到剪贴板
    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val clip = android.content.ClipData.newPlainText("search_results", text)
        clipboard.setPrimaryClip(clip)
    }

    // 将选中的搜索结果添加到AI对话
    private fun addResultsToAIChat(selectedResults: List<Map<String, Any>>) {
        val message = buildString {
            appendLine("📊 搜索结果分析请求：")
            appendLine()
            appendLine("数据类型: $searchDataType")
            appendLine("选中 ${selectedResults.size} 条结果：")
            appendLine()
            for ((i, r) in selectedResults.withIndex()) {
                val addr = r["address"] as String
                val v = r["value"]
                val mc = r["machineCode"] as? String ?: ""
                if (mc.isNotEmpty()) {
                    appendLine("${i+1}. 地址: $addr, 机器码: $mc, 值: $v")
                } else {
                    appendLine("${i+1}. 地址: $addr, 值: $v")
                }
            }
            appendLine()
            appendLine("请帮我分析这些内存地址的含义，以及可能的修改方案。")
        }

        // 添加到聊天记录
        chatMessages.add(Pair("👤 我", message))

        // 如果AI对话面板是打开的，直接刷新显示
        // 否则在下次打开时会自动显示
        Toast.makeText(this, "已添加到AI对话，请打开AI对话面板查看", Toast.LENGTH_SHORT).show()
    }

    private fun miniBtn(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text; setTextColor(Color.parseColor("#F2F3F8")); textSize = 10f
            background = GradientDrawable().apply { cornerRadius = dp(4).toFloat(); setColor(Color.parseColor("#3D5AFE")) }
            setPadding(dp(6), dp(0), dp(6), dp(0))
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(28))
            setOnClickListener { onClick() }
        }
    }

    private fun showWriteDialog(addr: String, curVal: Any?, machineCode: String = "") {
        makeDraggablePanel("修改内存值", { content ->
            content.addView(TextView(this).apply { text = "地址: $addr"; setTextColor(Color.parseColor("#4A6572")); textSize = 12f; setPadding(dp(12), dp(8), dp(12), dp(2)) })
            if (machineCode.isNotEmpty()) {
                content.addView(TextView(this).apply { text = "机器码: $machineCode"; setTextColor(Color.parseColor("#3D5AFE")); textSize = 11f; setPadding(dp(12), dp(2), dp(12), dp(2)) })
            }
            content.addView(TextView(this).apply { text = "当前值: $curVal"; setTextColor(Color.parseColor("#4A6572")); textSize = 12f; setPadding(dp(12), dp(2), dp(12), dp(8)) })

            val inp = EditText(this).apply {
                hint = "输入新值"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                background = GradientDrawable().apply { cornerRadius = dp(8).toFloat(); setColor(Color.parseColor("#304FFE")) }
                setPadding(dp(12), dp(8), dp(12), dp(8))
                inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                setText(curVal.toString())
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(12); marginEnd = dp(12) }
            }
            content.addView(inp)

            val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(12), dp(12), dp(8)) }
            bar.addView(smallBtn("取消") { showSearchPanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            bar.addView(smallBtn("确认修改") {
                val nv = inp.text.toString()
                if (nv.isEmpty()) return@smallBtn
                val addrLong = addr.removePrefix("0x").removePrefix("0X").toLongOrNull(16) ?: return@smallBtn
                Thread {
                    val numVal: Any = when (searchDataType) {
                        "float", "double" -> nv.toDoubleOrNull() ?: 0.0
                        else -> nv.toLongOrNull() ?: 0
                    }
                    val success = MemoryEngine.writeMemory(addrLong, numVal, searchDataType)
                    // 修改完成后更新列表中该地址的值
                    if (success) {
                        searchResults = searchResults.map { r ->
                            val rAddr = (r["addressInt"] as? Number)?.toLong()
                            if (rAddr == addrLong) {
                                r.toMutableMap().apply { this["value"] = numVal }
                            } else r
                        }
                    }
                    handler.post {
                        if (success) {
                            Toast.makeText(this@OverlayService, "✅ 修改成功: $addr = $numVal", Toast.LENGTH_SHORT).show()
                            showSearchPanel()
                        } else {
                            Toast.makeText(this@OverlayService, "❌ 修改失败", Toast.LENGTH_SHORT).show()
                        }
                    }
                }.start()
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(bar)
        }, 280, 280, onBack = { showSearchPanel() })
    }

    // 批量编辑对话框（支持单条和多条）
    private fun showBatchEditDialog(selectedResults: List<Map<String, Any>>) {
        val count = selectedResults.size
        makeDraggablePanel("编辑 $count 条数据", { content ->
            // 显示选中的地址列表（机器码+值）
            val addrList = selectedResults.joinToString("\n") { r ->
                val addr = r["address"] as String
                val v = r["value"]
                val mc = r["machineCode"] as? String ?: ""
                if (mc.isNotEmpty()) "$mc = $v" else "$addr = $v"
            }
            content.addView(TextView(this).apply {
                text = addrList; setTextColor(Color.parseColor("#4A6572")); textSize = 11f
                setPadding(dp(12), dp(8), dp(12), dp(8))
                maxLines = 6
            })

            // 输入新值
            content.addView(TextView(this).apply {
                text = "输入新值（将应用到所有 $count 条数据）："; setTextColor(Color.parseColor("#F2F3F8")); textSize = 12f
                setPadding(dp(12), dp(8), dp(12), dp(4))
            })

            val inp = EditText(this).apply {
                hint = "输入新值"; setTextColor(Color.parseColor("#FFFFFF")); setHintTextColor(Color.parseColor("#FFFFFF"))
                background = GradientDrawable().apply { cornerRadius = dp(8).toFloat(); setColor(Color.parseColor("#304FFE")) }
                setPadding(dp(12), dp(8), dp(12), dp(8))
                inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(12); marginEnd = dp(12) }
            }
            content.addView(inp)

            // 按钮
            val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(12), dp(12), dp(8)) }
            bar.addView(smallBtn("取消") { showSearchPanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            bar.addView(smallBtn("确认修改") {
                val nv = inp.text.toString()
                if (nv.isEmpty()) return@smallBtn

                val numVal: Any = when (searchDataType) {
                    "float", "double" -> nv.toDoubleOrNull() ?: 0.0
                    else -> nv.toLongOrNull() ?: 0
                }

                Thread {
                    var successCount = 0
                    for (r in selectedResults) {
                        val addr = r["address"] as String
                        val addrLong = addr.removePrefix("0x").removePrefix("0X").toLongOrNull(16) ?: continue
                        val success = MemoryEngine.writeMemory(addrLong, numVal, searchDataType)
                        if (success) {
                            successCount++
                            // 更新 searchResults 中对应地址的值
                            searchResults = searchResults.map { sr ->
                                val srAddr = (sr["addressInt"] as? Number)?.toLong()
                                if (srAddr == addrLong) {
                                    sr.toMutableMap().apply { this["value"] = numVal }
                                } else sr
                            }
                        }
                    }
                    handler.post {
                        if (successCount == count) {
                            Toast.makeText(this@OverlayService, "✅ 成功修改 $successCount 条数据为 $numVal", Toast.LENGTH_SHORT).show()
                        } else {
                            Toast.makeText(this@OverlayService, "⚠️ 修改完成：成功 $successCount/$count 条", Toast.LENGTH_SHORT).show()
                        }
                        selectedIndices.clear()
                        showSearchPanel()
                    }
                }.start()
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(bar)
        }, 300, 350)
    }

    // ==================== 跳转到主应用 ====================

    private fun jumpToPage(page: String) {
        closePanel()
        try {
            // 保存到 SharedPreferences 作为备用
            val prefs = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE)
            prefs.edit().putString("pending_page", page).apply()
            
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("page", page)
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ==================== AI 对话面板 ====================

    private fun showAIChatPanel() {
        saveLastPanel("chat")
        makeDraggablePanel("AI 对话", { content ->
            // AI 对话深色主题覆盖
            content.setBackgroundColor(Color.parseColor("#213333"))

            // 获取附加进程信息
            val prefs = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE)
            val attachedPid = prefs.getInt("attached_pid", -1)
            val attachedName = prefs.getString("attached_name", "")
            val attachedPackage = prefs.getString("attached_package", "")

            // 状态显示
            val status = TextView(this).apply {
                text = if (attachedPid != -1 && !attachedName.isNullOrEmpty()) {
                    "✅ 已附加: $attachedName"
                } else {
                    "⚠️ 未附加进程，请先附加游戏"
                }
                setTextColor(if (attachedPid != -1) Color.parseColor("#66BB6A") else Color.parseColor("#FF8F00"))
                textSize = 11f
                setPadding(dp(12), dp(8), dp(12), dp(4))
            }
            content.addView(status)

            // 分割线
            content.addView(View(this).apply {
                setBackgroundColor(Color.parseColor("#304FFE"))
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1))
            })

            // 消息显示区域
            val messageArea = ScrollView(this).apply {
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
                background = GradientDrawable().apply {
                    cornerRadius = dp(8).toFloat()
                    setColor(Color.parseColor("#213333"))
                }
            }
            val messageList = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(8), dp(8), dp(8), dp(8))
            }

            // 如果是首次打开，添加欢迎消息
            if (chatMessages.isEmpty()) {
                val welcomeMsg = if (attachedPid != -1 && !attachedName.isNullOrEmpty()) {
                    "🤖 AI 助手已就绪！\n\n当前已附加: $attachedName\n\n请告诉我你想修改什么游戏数据？\n\n💡 提示：如果切换其他附加进程后，记得清空聊天，以免 AI 读错上下文"
                } else {
                    "🤖 AI 助手\n\n⚠️ 请先附加游戏进程\n点击返回 → 附加进程"
                }
                chatMessages.add(Pair("🤖 AI", welcomeMsg))
            }

            // 恢复所有历史消息
            for ((sender, msg) in chatMessages) {
                val isUser = sender == "👤 我"
                messageList.addView(createMessageBubble(sender, msg, isUser))
            }

            messageArea.addView(messageList)
            content.addView(messageArea)

            // 恢复滚动位置，或滚动到底部
            if (savedScrollY > 0) {
                val restoreY = savedScrollY
                savedScrollY = 0
                messageArea.post { messageArea.scrollY = restoreY }
                // WebView 异步加载后再次恢复（内容高度变化会导致位置偏移）
                messageArea.postDelayed({ messageArea.scrollY = restoreY }, 500)
                messageArea.postDelayed({ messageArea.scrollY = restoreY }, 1500)
            } else {
                messageArea.post { messageArea.fullScroll(ScrollView.FOCUS_DOWN) }
                messageArea.postDelayed({ messageArea.fullScroll(ScrollView.FOCUS_DOWN) }, 500)
                messageArea.postDelayed({ messageArea.fullScroll(ScrollView.FOCUS_DOWN) }, 1500)
            }

            // 输入区域
            val inputArea = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(5), dp(5), dp(5), dp(5))
                setBackgroundColor(Color.parseColor("#213333"))
            }

            val inputField = EditText(this).apply {
                hint = "输入你的需求..."
                setTextColor(Color.parseColor("#000000"))
                setHintTextColor(Color.parseColor("#4A6572"))
                textSize = 13f
                background = GradientDrawable().apply {
                    cornerRadius = dp(6).toFloat()
                    setColor(Color.parseColor("#304FFE"))
                    setStroke(dp(1), Color.WHITE)
                }
                setPadding(dp(5), dp(5), dp(5), dp(5))
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)

                isFocusable = true
                isFocusableInTouchMode = true

                setOnClickListener {
                    requestFocus()
                    post {
                        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                        imm.showSoftInput(this, android.view.inputmethod.InputMethodManager.SHOW_FORCED)
                    }
                }

                setOnFocusChangeListener { _, hasFocus ->
                    if (hasFocus) {
                        post {
                            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                            imm.showSoftInput(this, android.view.inputmethod.InputMethodManager.SHOW_FORCED)
                        }
                    }
                }

                post {
                    requestFocus()
                    val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                    imm.showSoftInput(this, android.view.inputmethod.InputMethodManager.SHOW_FORCED)
                }
            }

            val sendBtn = TextView(this).apply {
                text = "发送"
                setTextColor(Color.parseColor("#F2F3F8"))
                textSize = 12f
                gravity = android.view.Gravity.CENTER
                background = GradientDrawable().apply {
                    cornerRadius = dp(6).toFloat()
                    setColor(Color.parseColor("#536DFE"))
                }
                setPadding(dp(5), dp(5), dp(5), dp(5))
                setOnClickListener {
                    val userInput = inputField.text.toString().trim()
                    if (userInput.isNotEmpty() && !isAiResponding) {
                        // 添加用户消息到历史
                        chatMessages.add(Pair("👤 我", userInput))
                        messageList.addView(createMessageBubble("👤 我", userInput, true))
                        inputField.text.clear()

                        // 隐藏输入法
                        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                        imm.hideSoftInputFromWindow(inputField.windowToken, 0)

                        // 创建流式输出气泡
                        isAiResponding = true
                        val streamBubble = LinearLayout(this@OverlayService).apply {
                            orientation = LinearLayout.VERTICAL
                            layoutParams = LinearLayout.LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                LinearLayout.LayoutParams.WRAP_CONTENT
                            ).apply { bottomMargin = dp(8) }
                        }
                        streamBubble.addView(TextView(this@OverlayService).apply {
                            text = "🤖 AI"
                            setTextColor(Color.parseColor("#3D5AFE"))
                            textSize = 11f
                            setPadding(0, 0, 0, dp(2))
                        })
                        val streamText = TextView(this@OverlayService).apply {
                            text = "正在思考..."
                            setTextColor(Color.parseColor("#F2F3F8"))
                            textSize = 12f
                            background = GradientDrawable().apply {
                                cornerRadius = dp(8).toFloat()
                                setColor(Color.parseColor("#304FFE"))
                            }
                            setPadding(dp(12), dp(8), dp(12), dp(8))
                        }
                        streamBubble.addView(streamText)
                        messageList.addView(streamBubble)
                        messageArea.post { messageArea.fullScroll(ScrollView.FOCUS_DOWN) }

                        // 调用 LLM API（支持 function calling）
                        Thread {
                            try {
                                val result = callLlmApi(userInput, attachedName ?: "")
                                handler.post {
                                    chatMessages.add(Pair("🤖 AI", result))
                                    isAiResponding = false
                                    streamBubble.removeView(streamText)
                                    streamBubble.addView(createMarkdownWebView(result))
                                    messageArea.post { messageArea.fullScroll(ScrollView.FOCUS_DOWN) }
                                }
                            } catch (e: Exception) {
                                handler.post {
                                    val errorMsg = "❌ 请求失败: ${e.message}\n\n请检查设置中的 API 配置"
                                    chatMessages.add(Pair("🤖 AI", errorMsg))
                                    isAiResponding = false
                                    streamBubble.removeView(streamText)
                                    streamBubble.addView(createMarkdownWebView(errorMsg))
                                    messageArea.post { messageArea.fullScroll(ScrollView.FOCUS_DOWN) }
                                }
                            }
                        }.start()
                    }
                }
            }

            inputArea.addView(inputField)
            inputArea.addView(sendBtn)
            content.addView(inputArea)

            // 底部按钮栏：保存聊天 + 清空聊天 + 关闭窗口
            val actionBar = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(5), dp(5), dp(5), dp(5))
            }
            val smallBtnStyle = { text: String, onClick: () -> Unit ->
                TextView(this).apply {
                    this.text = text; setTextColor(Color.parseColor("#F2F3F8")); textSize = 10f
                    gravity = android.view.Gravity.CENTER
                    background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#536DFE")) }
                    setPadding(dp(5), dp(5), dp(5), dp(5))
                    setOnClickListener { onClick() }
                }
            }
            actionBar.addView(smallBtnStyle("保存") { saveChatToStorage() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            actionBar.addView(smallBtnStyle("清空") {
                chatMessages.clear()
                messageList.removeAllViews()
                val welcomeMsg = if (attachedPid != -1 && !attachedName.isNullOrEmpty()) {
                    "🤖 AI 助手已就绪！\n\n当前已附加: $attachedName\n\n请告诉我你想修改什么游戏数据？\n\n💡 提示：如果切换其他附加进程后，记得清空聊天，以免 AI 读错上下文"
                } else {
                    "🤖 AI 助手\n\n⚠️ 请先附加游戏进程"
                }
                chatMessages.add(Pair("🤖 AI", welcomeMsg))
                messageList.addView(createMessageBubble("🤖 AI", welcomeMsg, false))
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            actionBar.addView(smallBtnStyle("关闭") { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(actionBar)

            // 滚动到底部
            messageArea.post { messageArea.fullScroll(ScrollView.FOCUS_DOWN) }

        }, 320, 550, titleIcon = R.drawable.ai, bgColor = "#000000")
    }

    // 创建消息气泡（用户消息用 TextView，AI 消息用 WebView 渲染 Markdown/LaTeX/Mermaid）
    private fun createMessageBubble(sender: String, message: String, isUser: Boolean): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }

            // 发送者标签
            addView(TextView(this@OverlayService).apply {
                text = sender
                setTextColor(if (isUser) Color.parseColor("#3D5AFE") else Color.parseColor("#536DFE"))
                textSize = 11f
                setPadding(0, 0, 0, dp(2))
            })

            if (isUser) {
                // 用户消息用 TextView
                addView(TextView(this@OverlayService).apply {
                    text = message
                    setTextColor(Color.parseColor("#F2F3F8"))
                    textSize = 12f
                    background = GradientDrawable().apply {
                        cornerRadius = dp(8).toFloat()
                        setColor(Color.parseColor("#304FFE"))
                    }
                    setPadding(dp(12), dp(8), dp(12), dp(8))
                })
            } else {
                // AI 消息统一用 WebView 渲染（支持 Markdown、代码块、Mermaid 图表）
                // 边框由 HTML CSS 中的 .bubble-ai 样式处理
                addView(createMarkdownWebView(message))
            }
        }
    }

    /**
     * LaTeX 预处理（在转义之前处理原始 Markdown 内容）
     * 参考 chatbox 的 latex.ts：标准化 LaTeX 分隔符，保护代码块不被误解析
     */
    private fun preprocessLaTeX(content: String): String {
        var result = content

        // Step 1: 保护代码块（用占位符替换，防止内部被处理）
        val codeBlocks = mutableListOf<String>()
        val codeBlockRegex = Regex("(```[\\s\\S]*?```|`[^`\\n]+`)")
        result = codeBlockRegex.replace(result) { match ->
            codeBlocks.add(match.value)
            "<<CODE_BLOCK_${codeBlocks.size - 1}>>"
        }

        // Step 2: 保护已有的 LaTeX 表达式
        val latexExpressions = mutableListOf<String>()
        val latexRegex = Regex("(\\$\\$[\\s\\S]*?\\$\\$|\\$[^$\\n]*?\\$|\\\\\\[[\\s\\S]*?\\\\]|\\\\\\(.*?\\\\\\))")
        result = latexRegex.replace(result) { match ->
            latexExpressions.add(match.value)
            "<<LATEX_${latexExpressions.size - 1}>>"
        }

        // Step 3: 转义货币符号（$后跟数字的情况）
        result = result.replace(Regex("\\$(?=\\d)"), "\\$")

        // Step 4: 恢复 LaTeX 表达式
        result = result.replace(Regex("<<LATEX_(\\d+)>>")) { match ->
            val index = match.groupValues[1].toInt()
            latexExpressions[index]
        }

        // Step 5: 恢复代码块
        result = result.replace(Regex("<<CODE_BLOCK_(\\d+)>>")) { match ->
            val index = match.groupValues[1].toInt()
            codeBlocks[index]
        }

        // Step 6: 标准化括号分隔符 \[...\] -> $$...$$，\(...\) -> $...$
        val bracketRegex = Regex("(```[\\S\\s]*?```|`.*?`)|\\\\\\[([\\S\\s]*?[^\\\\])\\\\]|\\\\\\((.*?)\\\\\\)")
        result = bracketRegex.replace(result) { match ->
            when {
                match.groupValues[1].isNotEmpty() -> match.groupValues[1] // 代码块，跳过
                match.groupValues[2].isNotEmpty() -> "$$${match.groupValues[2]}$$" // \[...\] -> $$...$$
                match.groupValues[3].isNotEmpty() -> "$${match.groupValues[3]}$" // \(...\) -> $...$
                else -> match.value
            }
        }

        return result
    }

    /**
     * 创建 WebView 渲染 Markdown/LaTeX/Mermaid
     */
    private fun createMarkdownWebView(markdownContent: String): WebView {
        // 仅转义 JS 字符串必须转义的字符：反斜杠、单引号、换行
        // $ 和 ` 不转义（占位符方式注入，不会触发 Kotlin 模板插值）
        val escapedContent = markdownContent
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
            .replace("\r", "")

        val html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        font-size: 14px;
        line-height: 1.6;
        color: #213333;
        background: #F2F3F8;
        padding: 10px;
        word-wrap: break-word;
        overflow-wrap: break-word;
    }
    h1, h2, h3, h4, h5, h6 {
        color: #304FFE;
        margin: 12px 0 6px 0;
        font-weight: 600;
    }
    h1 { font-size: 20px; }
    h2 { font-size: 17px; }
    h3 { font-size: 15px; }
    p { margin: 6px 0; }
    a { color: #3D5AFE; text-decoration: none; }
    code {
        background: #E8EAF6;
        color: #304FFE;
        padding: 2px 6px;
        border-radius: 4px;
        font-family: 'Courier New', monospace;
        font-size: 13px;
    }
    pre {
        background: #213333;
        border: 1px solid #3D5AFE;
        border-radius: 8px;
        padding: 12px;
        margin: 8px 0;
        overflow-x: auto;
    }
    pre code {
        background: none;
        padding: 0;
        color: #F2F3F8;
        font-size: 13px;
    }
    blockquote {
        border-left: 4px solid #3D5AFE;
        padding-left: 12px;
        margin: 8px 0;
        color: #4A6572;
    }
    ul, ol { margin: 6px 0; padding-left: 24px; }
    li { margin: 3px 0; }
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 8px 0;
    }
    th, td {
        border: 1px solid #3D5AFE;
        padding: 6px 10px;
        text-align: left;
    }
    th { background: #213333; color: #F2F3F8; }
    hr { border: none; border-top: 1px solid #3D5AFE; margin: 12px 0; }
    img { max-width: 100%; border-radius: 8px; }
    strong { color: #213333; }
    em { color: #4A6572; }
    .mermaid {
        max-width: 100%;
        max-height: 400px;
        overflow: auto;
        -webkit-overflow-scrolling: touch;
        background: #213333;
        border-radius: 8px;
        padding: 8px;
        margin: 8px 0;
    }
    .mermaid svg {
        max-width: 100%;
        height: auto;
    }
    .table-wrapper {
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
        max-width: 100%;
    }
    /* 聊天气泡 */
    .msg { margin-bottom: 16px; }
    .msg-header { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; }
    .msg-icon { font-size: 14px; }
    .msg-sender { font-size: 12px; color: #4A6572; }
    .msg-time { font-size: 10px; color: #4A6572; }
    .msg-user .msg-header { justify-content: flex-end; }
    .bubble { padding: 10px 14px; border-radius: 12px; max-width: 85%; word-break: break-word; }
    .bubble-user { background: #3D5AFE; border: 1px solid #FFFFFF; border-radius: 12px; padding: 10px 14px; margin-left: auto; color: #FFFFFF; }
    .bubble-ai { background: #FFFFFF; border: 1px solid #3D5AFE; border-radius: 12px; padding: 10px 14px; }
    .msg-user .msg-sender { color: #3D5AFE; }
    .msg-ai .msg-sender { color: #536DFE; }
</style>
<!-- Prism.js 代码高亮 (本地) -->
<link rel="stylesheet" href="file:///android_asset/css/prism-tomorrow.min.css">
<script src="file:///android_asset/js/prism.min.js"></script>
<!-- KaTeX for LaTeX (本地) -->
<link rel="stylesheet" href="file:///android_asset/css/katex.min.css">
<script src="file:///android_asset/js/katex.min.js"></script>
<script src="file:///android_asset/js/auto-render.min.js"></script>
<!-- Marked for Markdown (本地) -->
<script src="file:///android_asset/js/marked.min.js"></script>
<!-- Mermaid for diagrams (本地) -->
<script src="file:///android_asset/js/mermaid.min.js"></script>
</head>
<body>
<div id="content"></div>
<script>
(function() {
    // 初始化 Mermaid
    mermaid.initialize({
        startOnLoad: false,
        theme: 'dark',
        themeVariables: {
            primaryColor: '#3D5AFE',
            primaryTextColor: '#E0E0E0',
            primaryBorderColor: '#E8EAF6',
            lineColor: '#3D5AFE',
            secondaryColor: '#FFFFFF',
            tertiaryColor: '#F2F3F8'
        }
    });

    // 配置 marked + Prism.js 代码高亮
    var renderer = new marked.Renderer();
    renderer.code = function(code, lang) {
        var codeText = (typeof code === 'object') ? code.text : code;
        var langStr = (typeof code === 'object') ? code.lang : lang;
        var escaped = codeText.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        if (langStr && Prism.languages[langStr]) {
            try {
                var highlighted = Prism.highlight(codeText, Prism.languages[langStr], langStr);
                return '<pre class="language-' + langStr + '"><code class="language-' + langStr + '">' + highlighted + '</code></pre>';
            } catch(e) {}
        }
        return '<pre class="language-' + (langStr || 'none') + '"><code class="language-' + (langStr || 'none') + '">' + escaped + '</code></pre>';
    };
    marked.setOptions({ breaks: true, gfm: true, renderer: renderer });

    var rawContent = '___CONTENT_PLACEHOLDER___';

    // ====== LaTeX 保护：在 marked 解析前，用占位符保护 LaTeX 表达式 ======
    var latexStore = [];
    function protectLaTeX(text) {
        // 保护代码块
        var codeBlocks = [];
        text = text.replace(/(```[\s\S]*?```|`[^`\n]+`)/g, function(m, c) {
            codeBlocks.push(c);
            return '\x00CODE' + (codeBlocks.length-1) + '\x00';
        });
        // 保护 $$...$$ (display)
        text = text.replace(/\$\$([\s\S]*?)\$\$/g, function(m, inner) {
            latexStore.push('$$' + inner + '$$');
            return '\x00LATEX' + (latexStore.length-1) + '\x00';
        });
        // 保护 $...$ (inline)
        text = text.replace(/\$([^\$\n]+?)\$/g, function(m, inner) {
            latexStore.push('$' + inner + '$');
            return '\x00LATEX' + (latexStore.length-1) + '\x00';
        });
        // 保护 \[...\] 和 \(...\)
        text = text.replace(/\\\[([\s\S]*?)\\\]/g, function(m, inner) {
            latexStore.push('$$' + inner + '$$');
            return '\x00LATEX' + (latexStore.length-1) + '\x00';
        });
        text = text.replace(/\\\((.*?)\\\)/g, function(m, inner) {
            latexStore.push('$' + inner + '$');
            return '\x00LATEX' + (latexStore.length-1) + '\x00';
        });
        // 恢复代码块
        text = text.replace(/\x00CODE(\d+)\x00/g, function(m, i) { return codeBlocks[parseInt(i)]; });
        return text;
    }

    // ====== 第一步：保护 LaTeX ======
    var protectedContent = protectLaTeX(rawContent);

    // ====== 第二步：marked 解析 Markdown ======
    var htmlContent = marked.parse(protectedContent);

    // ====== 第三步：恢复 LaTeX 占位符 ======
    htmlContent = htmlContent.replace(/\x00LATEX(\d+)\x00/g, function(m, i) {
        return '<span class="katex-placeholder" data-latex="' +
            latexStore[parseInt(i)].replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;') +
            '"></span>';
    });

    // ====== 第四步：注入 DOM ======
    document.getElementById('content').innerHTML = htmlContent;

    // ====== 第五步：分离 mermaid 代码块，转为 <div class="mermaid"> ======
    var mermaidBlocks = document.querySelectorAll('code.language-mermaid');
    mermaidBlocks.forEach(function(block, idx) {
        var pre = block.parentElement;
        var div = document.createElement('div');
        div.className = 'mermaid';
        div.textContent = block.textContent;
        pre.parentNode.replaceChild(div, pre);
    });

    // ====== 第六步：表格滚动包裹 ======
    document.querySelectorAll('#content table').forEach(function(table) {
        var wrapper = document.createElement('div');
        wrapper.className = 'table-wrapper';
        table.parentNode.insertBefore(wrapper, table);
        wrapper.appendChild(table);
    });

    // ====== 第七步：渲染 LaTeX (KaTeX) ======
    document.querySelectorAll('.katex-placeholder').forEach(function(el) {
        var latex = el.getAttribute('data-latex');
        try {
            var isDisplay = latex.substring(0, 2) === '$$';
            var tex = isDisplay ? latex.substring(2, latex.length - 2) : latex.substring(1, latex.length - 1);
            katex.render(tex, el, { displayMode: isDisplay, throwOnError: false });
        } catch(e) {
            el.textContent = latex;
            el.style.color = '#FF5252';
        }
    });

    // ====== 第八步：渲染 Mermaid（异步）并通知高度 ======
    var notifyDone = function() {
        // 告知 WebView 内容已全部渲染完毕，可以测量高度
        window.__renderDone = true;
    };

    if (mermaidBlocks.length > 0) {
        // 兼容 mermaid v10 (run) 和 v8/v9 (init)
        if (typeof mermaid.run === 'function') {
            mermaid.run().then(function() { notifyDone(); }).catch(function(e) {
                console.error('Mermaid error:', e);
                notifyDone();
            });
        } else if (typeof mermaid.init === 'function') {
            try { mermaid.init(undefined, document.querySelectorAll('.mermaid')); } catch(e) { console.error(e); }
            notifyDone();
        } else {
            notifyDone();
        }
    } else {
        notifyDone();
    }
})();
</script>
</body>
</html>
""".trimIndent().replace("___CONTENT_PLACEHOLDER___", escapedContent)

        return WebView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setBackgroundColor(Color.TRANSPARENT)
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = true
                allowContentAccess = true
                loadWithOverviewMode = true
                useWideViewPort = true
                builtInZoomControls = false
                displayZoomControls = false
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    // 等待渲染完成（含 mermaid 异步）后再测量高度
                    view?.evaluateJavascript(
                        """
                        (function() {
                            function checkAndMeasure() {
                                if (window.__renderDone) {
                                    return document.body.scrollHeight;
                                }
                                // 每 100ms 检查一次，最多 5 秒
                                var tries = 0;
                                var timer = setInterval(function() {
                                    tries++;
                                    if (window.__renderDone || tries > 50) {
                                        clearInterval(timer);
                                        var h = document.body.scrollHeight;
                                        window.__measuredHeight = h;
                                    }
                                }, 100);
                                return -1;
                            }
                            return checkAndMeasure();
                        })();
                        """.trimIndent()
                    ) { value ->
                        try {
                            val initial = value.replace("\"", "").toFloatOrNull() ?: 0f
                            if (initial > 0) {
                                // 渲染已完成，直接调整
                                val layoutParams = this@apply.layoutParams
                                layoutParams.height = (initial * resources.displayMetrics.density).toInt() + dp(20)
                                this@apply.layoutParams = layoutParams
                            } else {
                                // 等待异步渲染完成后轮询高度
                                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                                val checkRunnable = object : Runnable {
                                    override fun run() {
                                        view?.evaluateJavascript("window.__measuredHeight || document.body.scrollHeight") { v ->
                                            try {
                                                val h = v.replace("\"", "").toFloatOrNull() ?: 0f
                                                if (h > 0) {
                                                    val lp = this@apply.layoutParams
                                                    lp.height = (h * resources.displayMetrics.density).toInt() + dp(20)
                                                    this@apply.layoutParams = lp
                                                } else {
                                                    handler.postDelayed(this, 200)
                                                }
                                            } catch (_: Exception) {}
                                        }
                                    }
                                }
                                handler.postDelayed(checkRunnable, 200)
                            }
                        } catch (_: Exception) {}
                    }
                }
            }
            loadDataWithBaseURL("file:///android_asset/", html, "text/html", "UTF-8", null)
        }
    }

    // ==================== 真实 LLM API 调用 ====================

    private fun callLlmApi(userInput: String, attachedApp: String): String {
        // 从 SharedPreferences 读取 LLM 配置（由主应用保存）
        val configPrefs = getSharedPreferences("gg_llm_config", Context.MODE_PRIVATE)
        val configJson = configPrefs.getString("config", null)

        var baseUrl = ""
        var apiKey = ""
        var model = "deepseek-chat"

        if (configJson != null) {
            try {
                val json = JSONObject(configJson)
                baseUrl = json.optString("baseUrl", "")
                apiKey = json.optString("apiKey", "")
                model = json.optString("model", "deepseek-chat")
            } catch (e: Exception) {
                // 解析失败，使用默认值
            }
        }

        // 如果没有配置 API，返回提示
        if (baseUrl.isEmpty() || apiKey.isEmpty()) {
            return "⚠️ 请先在设置中配置 LLM API\n\n打开主应用 → 设置 → LLM API 配置\n\n当前支持：DeepSeek、OpenAI、小米 MiMo 等"
        }

        // 构建系统提示（注入当前模型信息）
        val modelInfo = getModelInfo(model)
        val systemPrompt = buildString {
            append("你是 GG-AI 游戏内存修改助手。你当前使用的底层大模型是：$modelInfo。\n")
            append("当用户问你是什么模型时，你必须回答「$modelInfo」，这是你真实运行的底层模型。GG-AI 只是这个应用的名称，不是你的模型名称。不要编造其他模型名称。\n\n")
            append("## 核心行为准则\n")
            append("当用户要求搜索、读取、修改内存数据时，你必须调用工具（search_memory / read_memory / write_memory）来执行真实操作，返回真实结果。\n")
            append("绝对不要模拟、编造搜索结果或内存地址。不要在回复中写 gg.searchNumber 等代码来代替真实操作。\n")
            append("搜索结果中的「机器码」是该地址处的原始字节，可用于判断地址是否正确。\n")
            append("修改值后，工具会自动回读验证。如果回读值与目标不同，说明写入可能失败。\n\n")
            append("## 脚本生成\n")
            append("只有当用户明确说「写脚本」「生成脚本」「写个lua」等要求生成脚本时，才输出 Lua 脚本。\n")
            append("Lua 脚本规范（luaj-jse-3.0.2.jar 环境）：\n")
            append("- 使用 GG API：gg.searchNumber、gg.getResults、gg.editAll、gg.clearResults\n")
            append("- type 常量：gg.TYPE_DWORD、gg.TYPE_FLOAT、gg.TYPE_DOUBLE、gg.TYPE_BYTE、gg.TYPE_WORD、gg.TYPE_QWORD\n")
            append("- UI：gg.toast、gg.alert、gg.prompt、gg.choice\n")
            append("- 用 ```lua 代码块包裹\n\n")
            if (attachedApp.isNotEmpty()) {
                append("当前已附加游戏进程: $attachedApp\n")
            }
            append("\n渲染支持：当前客户端支持 Markdown 渲染、代码块高亮、LaTeX 数学公式和 Mermaid 图表。")
            append("当用户要求画图、画表、画流程图、架构图、思维导图、时序图、甘特图等可视化内容时，你必须直接输出 Mermaid 代码块，不要解释，不要用文字描述，直接给出代码。")
            append("用 ```mermaid 代码块包裹，客户端会自动渲染成图表。\n")
            append("⚠️ Mermaid 版本为 8.14.0，必须严格使用该版本兼容语法：\n")
            append("- 流程图用 `graph TD` 或 `graph LR`（不要用 flowchart）\n")
            append("- 支持的图表类型：graph、sequenceDiagram、classDiagram、stateDiagram、gantt、pie\n")
            append("- 不支持：mindmap、timeline、quadrantChart、block-beta、sankey-beta、xychart-beta 等新类型\n")
            append("- 不要使用 `%%{init: ...}%%` 配置指令\n")
            append("- 节点文本中的特殊字符用双引号包裹，如 A[\"(特殊)文本\"]\n")
            append("示例：\n")
            append("```mermaid\ngraph TD\n    A[搜索金币值] --> B[消费金币]\n    B --> C[再次搜索]\n    C --> D[确认地址]\n    D --> E[修改值]\n```\n\n")
            append("LaTeX 公式支持：用 ${'$'}...${'$'} 包裹行内公式，${'$'}${'$'}...${'$'}${'$'} 包裹独立公式。示例：${'$'}E=mc^2${'$'}，${'$'}${'$'}\\int_0^1 x dx = \\frac{1}{2}${'$'}${'$'}\n\n")
            append("回复格式：\n")
            append("- 使用简洁友好的中文\n")
            append("- 操作步骤用编号列出\n")
            append("- 执行结果用 ✅ 或 ❌ 标记\n")
            append("- 地址和数值用代码格式显示\n")
            append("- 用户要求画图时，直接输出 mermaid 代码块，不要多余文字\n\n")

            // 读取已启用的 Skill
            try {
                val skillsPrefs = getSharedPreferences("gg_skills", Context.MODE_PRIVATE)
                val skillsJson = skillsPrefs.getString("skills", "[]") ?: "[]"
                val skillsArray = org.json.JSONArray(skillsJson)
                if (skillsArray.length() > 0) {
                    append("## 已导入的 Skill\n")
                    append("以下 Skill 已启用，请在回复时参考和运用这些 Skill 的知识：\n\n")
                    for (i in 0 until skillsArray.length()) {
                        val skill = skillsArray.getJSONObject(i)
                        val name = skill.optString("name", "未知")
                        val content = skill.optString("content", "")
                        append("### 📖 $name\n")
                        append("$content\n\n")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("GG-AI", "Failed to load skills: $e")
            }
        }

        // 构建消息历史（最近 10 条）
        val messages = JSONArray()
        messages.put(JSONObject().apply {
            put("role", "system")
            put("content", systemPrompt)
        })

        val recentMessages = chatMessages.takeLast(10)
        for ((sender, msg) in recentMessages) {
            val role = if (sender == "👤 我") "user" else "assistant"
            messages.put(JSONObject().apply {
                put("role", role)
                put("content", msg)
            })
        }

        // 添加当前用户消息
        messages.put(JSONObject().apply {
            put("role", "user")
            put("content", userInput)
        })

        // 检测是否是 Gemini API
        val isGemini = baseUrl.contains("generativelanguage.googleapis.com")
        // Gemini 使用 OpenAI 兼容接口: /v1beta/openai/
        // 避免重复添加 /v1beta/openai
        val effectiveBaseUrl = if (isGemini) {
            val base = baseUrl.trimEnd('/')
            if (base.endsWith("/v1beta/openai")) base else "$base/v1beta/openai"
        } else {
            baseUrl.trimEnd('/')
        }

        // 定义工具
        val tools = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "function")
                put("function", JSONObject().apply {
                    put("name", "search_memory")
                    put("description", "在游戏内存中搜索数值。支持精确搜索、范围搜索、AOB搜索。返回匹配的内存地址列表。")
                    put("parameters", JSONObject().apply {
                        put("type", "object")
                        put("properties", JSONObject().apply {
                            put("mode", JSONObject().apply {
                                put("type", "string")
                                put("description", "搜索模式：exact(精确)、range(范围)、aob(AOB特征码)")
                                put("enum", JSONArray().apply { put("exact"); put("range"); put("aob") })
                            })
                            put("value", JSONObject().apply {
                                put("type", "string")
                                put("description", "搜索值。exact模式填数值如'750000'；range模式填'最小值,最大值'如'100,200'；aob模式填特征码如'48 8B 05 ?? ??'")
                            })
                            put("type", JSONObject().apply {
                                put("type", "string")
                                put("description", "数据类型：dword(整数4字节)、float(浮点)、double(双精度)、byte(1字节)、word(2字节)、qword(8字节)")
                                put("enum", JSONArray().apply { put("dword"); put("float"); put("double"); put("byte"); put("word"); put("qword") })
                            })
                        })
                        put("required", JSONArray().apply { put("mode"); put("value") })
                    })
                })
            })
            put(JSONObject().apply {
                put("type", "function")
                put("function", JSONObject().apply {
                    put("name", "read_memory")
                    put("description", "从指定内存地址读取值。")
                    put("parameters", JSONObject().apply {
                        put("type", "object")
                        put("properties", JSONObject().apply {
                            put("address", JSONObject().apply {
                                put("type", "string")
                                put("description", "内存地址，十六进制如'0x12345678'")
                            })
                            put("type", JSONObject().apply {
                                put("type", "string")
                                put("description", "数据类型")
                                put("enum", JSONArray().apply { put("dword"); put("float"); put("double"); put("byte"); put("word"); put("qword") })
                            })
                        })
                        put("required", JSONArray().apply { put("address"); put("type") })
                    })
                })
            })
            put(JSONObject().apply {
                put("type", "function")
                put("function", JSONObject().apply {
                    put("name", "write_memory")
                    put("description", "向指定内存地址写入值。")
                    put("parameters", JSONObject().apply {
                        put("type", "object")
                        put("properties", JSONObject().apply {
                            put("address", JSONObject().apply {
                                put("type", "string")
                                put("description", "内存地址，十六进制如'0x12345678'")
                            })
                            put("value", JSONObject().apply {
                                put("type", "string")
                                put("description", "要写入的值")
                            })
                            put("type", JSONObject().apply {
                                put("type", "string")
                                put("description", "数据类型")
                                put("enum", JSONArray().apply { put("dword"); put("float"); put("double"); put("byte"); put("word"); put("qword") })
                            })
                        })
                        put("required", JSONArray().apply { put("address"); put("value"); put("type") })
                    })
                })
            })
        }

        // 统一使用 OpenAI 兼容接口（Gemini 使用 /v1beta/openai/）
        val url = URL("$effectiveBaseUrl/chat/completions")
        android.util.Log.d("GG-AI", "API URL: $url")
        android.util.Log.d("GG-AI", "Model: $model")

        val requestBody = JSONObject().apply {
            put("model", model)
            put("messages", messages)
            put("tools", tools)
            put("temperature", 0.7)
            put("max_tokens", 2048)
        }

        val responseText = doHttpPost(url, apiKey, requestBody)
        val responseJson = JSONObject(responseText)
        val choices = responseJson.getJSONArray("choices")
        if (choices.length() == 0) return "❌ 未收到 AI 回复"

        val msg = choices.getJSONObject(0).getJSONObject("message")

        // 检查是否有工具调用
        if (msg.has("tool_calls") && !msg.isNull("tool_calls")) {
            messages.put(msg)

            val toolCalls = msg.getJSONArray("tool_calls")
            for (i in 0 until toolCalls.length()) {
                val toolCall = toolCalls.getJSONObject(i)
                val callId = toolCall.getString("id")
                val func = toolCall.getJSONObject("function")
                val funcName = func.getString("name")
                val funcArgs = JSONObject(func.getString("arguments"))

                val result = executeToolCall(funcName, funcArgs)

                messages.put(JSONObject().apply {
                    put("role", "tool")
                    put("tool_call_id", callId)
                    put("content", result)
                })
            }

            val finalRequestBody = JSONObject().apply {
                put("model", model)
                put("messages", messages)
                put("temperature", 0.7)
                put("max_tokens", 2048)
            }
            val finalResponseText = doHttpPost(url, apiKey, finalRequestBody)
            val finalJson = JSONObject(finalResponseText)
            val finalChoices = finalJson.getJSONArray("choices")
            if (finalChoices.length() > 0) {
                return finalChoices.getJSONObject(0).getJSONObject("message").getString("content")
            }
            return "❌ 未收到 AI 回复"
        }

        return msg.optString("content", "❌ 未收到 AI 回复")
    }

    private fun doHttpPost(url: URL, apiKey: String, body: JSONObject): String {
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        conn.doOutput = true
        conn.connectTimeout = 30000
        conn.readTimeout = 60000
        val writer = OutputStreamWriter(conn.outputStream, Charsets.UTF_8)
        writer.write(body.toString())
        writer.flush()
        writer.close()
        val code = conn.responseCode
        android.util.Log.d("GG-AI", "HTTP Response: $code, URL: ${url}")
        if (code != 200) {
            val err = conn.errorStream?.bufferedReader()?.readText() ?: "未知错误"
            android.util.Log.e("GG-AI", "HTTP Error: $code, Body: $err")
            throw Exception("HTTP $code: $err")
        }
        val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
        val text = reader.readText()
        reader.close()
        conn.disconnect()
        return text
    }

    private fun executeToolCall(name: String, args: JSONObject): String {
        return try {
            when (name) {
                "search_memory" -> {
                    val mode = args.optString("mode", "exact")
                    val value = args.optString("value", "")
                    val type = args.optString("type", "dword")
                    if (MemoryEngine.getAttachedPid() == null) return "❌ 未附加游戏进程，请先附加"
                    when (mode) {
                        "exact" -> {
                            val numVal: Any = if (type == "float" || type == "double") value.toDoubleOrNull() ?: 0.0 else value.toLongOrNull() ?: 0
                            val res = MemoryEngine.searchExact(numVal, type)
                            if (res.isEmpty()) return "搜索完成，未找到结果"
                            val sb = StringBuilder("找到 ${res.size} 个结果：\n")
                            for ((idx, r) in res.take(50).withIndex()) {
                                val addr = r["address"] ?: ""
                                val mc = r["machineCode"] ?: ""
                                val v = r["value"] ?: ""
                                sb.append("${idx + 1}. $addr [$mc] = $v\n")
                            }
                            if (res.size > 50) sb.append("... 共 ${res.size} 个结果")
                            sb.append("\n请分析机器码判断哪个地址是目标数据，再使用 write_memory 修改。")
                            sb.toString()
                        }
                        "range" -> {
                            val parts = value.split(",")
                            if (parts.size != 2) return "❌ 范围格式错误，应为 '最小值,最大值'"
                            val lo = parts[0].trim().toLongOrNull() ?: 0
                            val hi = parts[1].trim().toLongOrNull() ?: 0
                            val res = MemoryEngine.searchByRange(lo, hi, type)
                            if (res.isEmpty()) return "搜索完成，未找到结果"
                            val sb = StringBuilder("找到 ${res.size} 个结果：\n")
                            for ((idx, r) in res.take(50).withIndex()) {
                                sb.append("${idx + 1}. 地址: ${r["address"]}, 值: ${r["value"]}\n")
                            }
                            sb.toString()
                        }
                        "aob" -> {
                            val res = MemoryEngine.searchAob(value)
                            if (res.isEmpty()) return "搜索完成，未找到结果"
                            val sb = StringBuilder("找到 ${res.size} 个结果：\n")
                            for ((idx, r) in res.take(50).withIndex()) {
                                sb.append("${idx + 1}. 地址: ${r["address"]}\n")
                            }
                            sb.toString()
                        }
                        else -> "❌ 未知搜索模式: $mode"
                    }
                }
                "read_memory" -> {
                    val address = args.optString("address", "")
                    val type = args.optString("type", "dword")
                    if (MemoryEngine.getAttachedPid() == null) return "❌ 未附加游戏进程"
                    val addrLong = address.removePrefix("0x").toLongOrNull(16) ?: return "❌ 无效地址: $address"
                    val value = MemoryEngine.readMemory(addrLong, type)
                    "地址 $address 的值: $value (类型: $type)"
                }
                "write_memory" -> {
                    val address = args.optString("address", "")
                    val value = args.optString("value", "")
                    val type = args.optString("type", "dword")
                    if (MemoryEngine.getAttachedPid() == null) return "❌ 未附加游戏进程"
                    val addrLong = address.removePrefix("0x").toLongOrNull(16) ?: return "❌ 无效地址: $address"
                    val numVal: Any = if (type == "float" || type == "double") value.toDoubleOrNull() ?: 0.0 else value.toLongOrNull() ?: 0
                    val success = MemoryEngine.writeMemory(addrLong, numVal, type)
                    if (success) {
                        // 写入后验证
                        val readBack = MemoryEngine.readMemory(addrLong, type)
                        "✅ 已写入 $value 到地址 $address，回读验证: $readBack"
                    } else {
                        "❌ 写入失败，可能是地址不可写或权限不足"
                    }
                }
                else -> "❌ 未知工具: $name"
            }
        } catch (e: Exception) {
            "❌ 执行出错: ${e.message}"
        }
    }

    // 流式调用 LLM API
    private fun callLlmApiStream(userInput: String, attachedApp: String, onChunk: (String) -> Unit) {
        val configPrefs = getSharedPreferences("gg_llm_config", Context.MODE_PRIVATE)
        val configJson = configPrefs.getString("config", null)

        var baseUrl = ""
        var apiKey = ""
        var model = "deepseek-chat"

        if (configJson != null) {
            try {
                val json = JSONObject(configJson)
                baseUrl = json.optString("baseUrl", "")
                apiKey = json.optString("apiKey", "")
                model = json.optString("model", "deepseek-chat")
            } catch (_: Exception) {}
        }

        if (baseUrl.isEmpty() || apiKey.isEmpty()) {
            onChunk("⚠️ 请先在设置中配置 LLM API")
            return
        }

        val modelInfo = getModelInfo(model)
        val systemPrompt = buildString {
            append("你是 GG-AI 游戏内存修改助手。你当前使用的底层大模型是：$modelInfo。\n")
            append("当用户问你是什么模型时，你必须回答「$modelInfo」。GG-AI 只是应用名称，不是模型名称。\n\n")
            append("当用户要求搜索/读取/修改内存时，调用 search_memory/read_memory/write_memory 工具执行真实操作，绝对不要模拟结果。\n")
            append("只有用户明确要求写脚本时才输出 Lua 脚本（luaj-jse-3.0.2.jar），用 ```lua 包裹。\n\n")
            if (attachedApp.isNotEmpty()) append("当前已附加游戏进程: $attachedApp\n")
            append("\n渲染支持：客户端支持 Markdown、LaTeX 公式（${'$'}...${'$'} / ${'$'}${'$'}...${'$'}${'$'}）和 Mermaid 图表。")
            append("用户要求画图时，必须直接输出 ```mermaid 代码块，不要解释。")
            append("Mermaid 版本 8.14.0，只支持 graph/sequenceDiagram/classDiagram/stateDiagram/gantt/pie，不要用 flowchart/mindmap/timeline 等新类型，不要用 %%{init}%% 指令，特殊字符用双引号包裹。")
            append("\n使用简洁友好的中文回复，操作步骤用编号列出。")
        }

        val messages = JSONArray()
        messages.put(JSONObject().apply { put("role", "system"); put("content", systemPrompt) })
        for ((sender, msg) in chatMessages.takeLast(10)) {
            messages.put(JSONObject().apply { put("role", if (sender == "👤 我") "user" else "assistant"); put("content", msg) })
        }
        messages.put(JSONObject().apply { put("role", "user"); put("content", userInput) })

        val isGemini = baseUrl.contains("generativelanguage.googleapis.com")
        val effectiveBaseUrl = if (isGemini) {
            "${baseUrl.trimEnd('/')}/v1beta/openai"
        } else {
            baseUrl.trimEnd('/')
        }

        // 统一使用 OpenAI 兼容接口（Gemini 使用 /v1beta/openai/）
        val url = URL("$effectiveBaseUrl/chat/completions")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        conn.doOutput = true
        conn.connectTimeout = 30000
        conn.readTimeout = 120000

        val requestBody = JSONObject().apply {
            put("model", model)
            put("messages", messages)
            put("temperature", 0.7)
            put("max_tokens", 2048)
            put("stream", true)
        }

        val writer = OutputStreamWriter(conn.outputStream, Charsets.UTF_8)
        writer.write(requestBody.toString())
        writer.flush()
        writer.close()

        val responseCode = conn.responseCode
        if (responseCode != 200) {
            val errorStream = conn.errorStream?.bufferedReader()?.readText() ?: "未知错误"
            throw Exception("HTTP $responseCode: $errorStream")
        }

        val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
        var line: String?
        while (reader.readLine().also { line = it } != null) {
            val l = line!!.trim()
            if (l.isEmpty() || !l.startsWith("data: ")) continue
            val data = l.substring(6)
            if (data == "[DONE]") break
            try {
                val json = JSONObject(data)
                val delta = json.getJSONArray("choices").getJSONObject(0).getJSONObject("delta")
                if (delta.has("content") && !delta.isNull("content")) {
                    val content = delta.getString("content")
                    if (content.isNotEmpty() && content != "null") {
                        onChunk(content)
                    }
                }
            } catch (_: Exception) {}
        }
        reader.close()
        conn.disconnect()
    }

    // 根据模型名称返回公司+版本信息
    private fun getModelInfo(modelName: String): String {
        val m = modelName.lowercase()
        return when {
            m.contains("deepseek-reasoner") || m.contains("deepseek-r1") -> "DeepSeek-R1（深度求索公司，推理增强模型）"
            m.contains("deepseek") -> "DeepSeek-V3（深度求索公司，通用对话模型）"
            m.contains("mimo") -> "MiMo-v2.5-Pro（小米公司，大语言模型）"
            m.contains("gpt-4o") -> "GPT-4o（OpenAI 公司，多模态模型）"
            m.contains("gpt-4") -> "GPT-4（OpenAI 公司，大语言模型）"
            m.contains("gpt-3.5") -> "GPT-3.5-Turbo（OpenAI 公司，大语言模型）"
            m.contains("gemini") -> "Gemini（Google 公司，大语言模型）"
            m.contains("claude") -> "Claude（Anthropic 公司，大语言模型）"
            m.contains("qwen") || m.contains("tongyi") -> "通义千问（阿里巴巴公司，大语言模型）"
            m.contains("glm") || m.contains("chatglm") -> "ChatGLM（智谱AI公司，大语言模型）"
            else -> modelName
        }
    }

    // ==================== 保存聊天到存储 ====================

    private fun saveChatToStorage() {
        if (chatMessages.isEmpty()) {
            handler.post {
                Toast.makeText(this, "没有聊天记录可保存", Toast.LENGTH_SHORT).show()
            }
            return
        }

        try {
            val prefs = getSharedPreferences("gg_overlay_chat", Context.MODE_PRIVATE)
            val editor = prefs.edit()

            // 保存为 JSON 数组
            val jsonArray = JSONArray()
            for ((sender, msg) in chatMessages) {
                jsonArray.put(JSONObject().apply {
                    put("sender", sender)
                    put("message", msg)
                    put("timestamp", System.currentTimeMillis())
                })
            }

            // 使用时间戳作为 key
            val sessionId = "chat_${System.currentTimeMillis()}"
            editor.putString(sessionId, jsonArray.toString())
            editor.putString("latest_session_id", sessionId)
            editor.apply()

            handler.post {
                Toast.makeText(this, "✅ 聊天已保存，可在主应用查看", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            handler.post {
                Toast.makeText(this, "❌ 保存失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // ==================== 脚本库面板 ====================

    private fun showScriptPanel() {
        saveLastPanel("script")
        makeDraggablePanel("脚本库", { content ->
            val status = TextView(this).apply {
                text = "正在加载脚本..."
                setTextColor(Color.parseColor("#F2F3F8"))
                textSize = 12f
                setPadding(dp(12), dp(8), dp(12), dp(4))
            }
            content.addView(status)

            val sv = ScrollView(this).apply {
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            }
            val list = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(8), dp(4), dp(8), dp(4))
            }
            sv.addView(list)
            content.addView(sv)

            // 加载脚本的函数
            fun loadScripts() {
                list.removeAllViews()
                status.text = "正在加载脚本..."
                Thread {
                    val scripts = loadScriptsFromStorage()
                    handler.post {
                        status.text = "找到 ${scripts.size} 个脚本"
                        for (script in scripts) {
                            val item = LinearLayout(this).apply {
                                orientation = LinearLayout.HORIZONTAL
                                setPadding(dp(12), dp(10), dp(12), dp(10))
                                background = GradientDrawable().apply {
                                    cornerRadius = dp(8).toFloat()
                                    setColor(Color.parseColor("#304FFE"))
                                }
                                layoutParams = LinearLayout.LayoutParams(
                                    LinearLayout.LayoutParams.MATCH_PARENT,
                                    LinearLayout.LayoutParams.WRAP_CONTENT
                                ).apply { bottomMargin = dp(6) }
                            }
                            val nameText = TextView(this).apply {
                                text = script["name"] ?: "未知脚本"
                                setTextColor(Color.parseColor("#F2F3F8"))
                                textSize = 14f
                                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                            }
                            item.addView(nameText)

                            val runBtn = smallBtn("▶ 运行") {
                                val scriptContent = script["content"] ?: ""
                                if (scriptContent.isNotEmpty()) {
                                    status.text = "正在运行: ${script["name"]}..."
                                    Thread {
                                        try {
                                            LuaEngine.setContext(this@OverlayService)
                                            val output = LuaEngine.executeScript(scriptContent)
                                            // 自动保存日志
                                            saveScriptLog(script["name"] ?: "脚本", output)
                                            handler.post {
                                                status.text = "✅ ${script["name"]} 执行完成"
                                                Toast.makeText(this@OverlayService, "✅ ${script["name"]} 执行完成，日志已保存", Toast.LENGTH_SHORT).show()
                                            }
                                        } catch (e: Exception) {
                                            handler.post {
                                                status.text = "❌ 执行失败: ${e.message}"
                                            }
                                        }
                                    }.start()
                                }
                            }
                            item.addView(runBtn)
                            list.addView(item)
                        }

                        if (scripts.isEmpty()) {
                            list.addView(TextView(this).apply {
                                text = "暂无脚本\n请在主应用脚本库中创建"
                                setTextColor(Color.parseColor("#4A6572"))
                                textSize = 13f
                                setPadding(dp(12), dp(20), dp(12), dp(8))
                                gravity = Gravity.CENTER
                            })
                        }
                    }
                }.start()
            }

            // 首次加载
            loadScripts()

            // 底部按钮：刷新 + 关闭窗口
            val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(4), dp(12), dp(8)) }
            bar.addView(iconBtn(R.drawable.shuaxing) { loadScripts() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            bar.addView(iconBtn(R.drawable.ck_gb) { closePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            content.addView(bar)
        }, 300, 420, titleIcon = R.drawable.jiaoben, bgColor = "#213333")
    }

    /**
     * 保存脚本运行日志
     */
    private fun saveScriptLog(scriptName: String, output: String) {
        try {
            val now = java.text.SimpleDateFormat("MMddHHmm", java.util.Locale.getDefault()).format(java.util.Date())
            val timeStr = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())

            // 保存到 gg_script_logs SharedPreferences（与 MainActivity 的 getOverlayScriptLogs 对应）
            val prefs = getSharedPreferences("gg_script_logs", Context.MODE_PRIVATE)
            val existing = prefs.getString("logs", "[]") ?: "[]"
            val logsArray = org.json.JSONArray(existing)

            val logEntry = org.json.JSONObject().apply {
                put("name", "${now}_$scriptName")
                put("scriptName", scriptName)
                put("time", timeStr)
                put("output", output)
            }
            logsArray.put(logEntry)

            prefs.edit().putString("logs", logsArray.toString()).apply()
        } catch (_: Exception) {}
    }

    /**
     * 从存储加载脚本列表
     */
    private fun loadScriptsFromStorage(): List<Map<String, String>> {
        val scripts = mutableListOf<Map<String, String>>()

        try {
            // 从 SharedPreferences 读取（由主应用同步，已包含内置脚本）
            val prefs = getSharedPreferences("gg_scripts", Context.MODE_PRIVATE)
            val scriptsJson = prefs.getString("scripts", "[]") ?: "[]"
            val jsonArray = org.json.JSONArray(scriptsJson)
            for (i in 0 until jsonArray.length()) {
                val json = jsonArray.getJSONObject(i)
                scripts.add(mapOf(
                    "id" to json.optString("id", ""),
                    "name" to json.optString("name", "未知"),
                    "content" to json.optString("content", ""),
                    "description" to json.optString("description", "")
                ))
            }
        } catch (_: Exception) {}

        // 如果没有从主应用同步到脚本，添加内置脚本作为备用
        if (scripts.none { it["id"] == "builtin_test" }) {
            // 添加内置脚本
            scripts.add(mapOf(
            "id" to "builtin_test",
            "name" to "运行测试",
            "content" to """-- 游戏修改器 Lua 测试脚本
function searchData(value, valueType)
    gg.clearResults()
    gg.searchNumber(value, valueType)
    local count = gg.getResultCount()
    gg.toast("搜索完成，找到 " .. count .. " 条结果")
    return count
end
function menu1_search()
    local choice = gg.choice({
        " 搜索整数 9999",
        " 搜索浮点 1.0",
        " 搜索双精度 3.14"
    }, nil, "【数值搜索】请选择搜索类型")
    if choice == nil then
        gg.toast("已取消")
        return
    end
    if choice == 1 then
        searchData(9999, gg.TYPE_DWORD)
    elseif choice == 2 then
        searchData("1.0", gg.TYPE_FLOAT)
    elseif choice == 3 then
        searchData("3.14", gg.TYPE_DOUBLE)
    end
end
function menu2_advanced()
    local choice = gg.choice({
        " 修改搜索结果为 88888",
        " 冻结当前结果",
        " 清除所有结果"
    }, nil, "【高级操作】请选择操作")
    if choice == nil then
        gg.toast("已取消")
        return
    end
    if choice == 1 then
        local count = gg.getResultCount()
        if count > 0 then
            local results = gg.getResults(count)
            for i, v in ipairs(results) do
                results[i].value = 88888
                results[i].flags = gg.TYPE_DWORD
            end
            gg.setValues(results)
            gg.toast("已修改 " .. count .. " 条数据为 88888")
        else
            gg.toast("没有搜索结果")
        end
    elseif choice == 2 then
        local count = gg.getResultCount()
        if count > 0 then
            local results = gg.getResults(count)
            for i, v in ipairs(results) do
                results[i].freeze = true
            end
            gg.addListItems(results)
            gg.toast("已冻结 " .. count .. " 条数据")
        else
            gg.toast("没有搜索结果")
        end
    elseif choice == 3 then
        gg.clearResults()
        gg.clearList()
        gg.toast("已清除所有结果")
    end
end
function mainMenu()
    while true do
        local main = gg.choice({
            " 数值搜索",
            " 高级操作",
            " 退出脚本"
        }, nil, "=== Lua 测试脚本 v1.0 ===")
        if main == nil or main == 3 then
            gg.toast("脚本已退出")
            break
        elseif main == 1 then
            menu1_search()
        elseif main == 2 then
            menu2_advanced()
        end
    end
end
gg.toast("Lua 测试脚本已加载")
gg.sleep(1000)
mainMenu()""",
            "description" to "Lua 菜单弹窗 + 数据搜索测试"
        ))
        }

        return scripts
    }

    /**
     * 显示脚本运行输出对话框
     */

    // ==================== UI 工具 ====================

    private fun menuBtn(text: String, iconRes: Int? = null, onClick: () -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply { cornerRadius = dp(8).toFloat(); setColor(Color.parseColor("#304FFE")) }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(6) }
            setOnClickListener { onClick() }
            if (iconRes != null) {
                addView(ImageView(this@OverlayService).apply {
                    setImageResource(iconRes)
                    layoutParams = LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(10) }
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                })
            }
            addView(TextView(this@OverlayService).apply {
                this.text = text; setTextColor(Color.parseColor("#F2F3F8")); textSize = 14f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
        }
    }

    private fun smallBtn(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text; setTextColor(Color.parseColor("#F2F3F8")); textSize = 11f
            background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#3D5AFE")) }
            setPadding(dp(10), dp(4), dp(10), dp(4))
            setOnClickListener { onClick() }
        }
    }

    private fun iconBtn(iconRes: Int, label: String = "", onClick: () -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(6).toFloat(); setColor(Color.parseColor("#3D5AFE")) }
            setPadding(dp(6), dp(4), dp(6), dp(4))
            setOnClickListener { onClick() }
            addView(ImageView(this@OverlayService).apply {
                setImageResource(iconRes)
                layoutParams = LinearLayout.LayoutParams(dp(20), dp(20))
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            })
            if (label.isNotEmpty()) {
                addView(TextView(this@OverlayService).apply {
                    text = label; setTextColor(Color.parseColor("#F2F3F8")); textSize = 9f
                    gravity = Gravity.CENTER
                })
            }
        }
    }

    private fun dp(v: Int): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()
}
