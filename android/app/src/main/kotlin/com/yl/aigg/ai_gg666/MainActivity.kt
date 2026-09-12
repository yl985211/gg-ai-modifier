package com.yl.aigg.ai_gg666

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        lateinit var appContext: android.content.Context
    }

    private lateinit var channel: MethodChannel
    private val OVERLAY_PERMISSION_REQUEST = 1234
    private val STORAGE_PERMISSION_REQUEST = 1235
    private val ALL_PERMISSIONS_REQUEST = 1236
    private var pendingPage: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        appContext = applicationContext
        
        // 初始化 MemoryEngine 的 Context
        MemoryEngine.setContext(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yl.aigg/bridge")
        
        // 首次启动时申请权限
        requestAllPermissionsOnFirstLaunch()

        // 检查启动时是否有页面参数
        val startPage = intent?.getStringExtra("page")
        if (startPage != null) {
            pendingPage = startPage
        }
        // 也检查 SharedPreferences
        if (pendingPage == null) {
            val prefs = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE)
            pendingPage = prefs.getString("pending_page", null)
            prefs.edit().remove("pending_page").apply()
        }
        
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // 获取悬浮窗传来的页面参数
                "getInitialPage" -> {
                    val page = pendingPage
                    pendingPage = null
                    result.success(page)
                }

                // 进程管理（后台线程执行，避免阻塞 UI）
                "getProcessList" -> {
                    Thread {
                        try {
                            val processes = ProcessManager.getProcessList(this@MainActivity as android.content.Context)
                            runOnUiThread { result.success(processes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PROCESS_LIST_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "attachProcess" -> {
                    val pid = call.argument<Int>("pid")
                    if (pid == null) {
                        result.error("INVALID_PID", "PID is required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val success = MemoryEngine.attachProcess(pid)
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ATTACH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "detachProcess" -> {
                    Thread {
                        try {
                            MemoryEngine.detachProcess()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DETACH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getAttachedPid" -> {
                    // 优先从 SharedPreferences 读取（悬浮窗可能已附加）
                    val prefs = getSharedPreferences("gg_overlay", Context.MODE_PRIVATE)
                    val savedPid = prefs.getInt("attached_pid", -1)
                    val currentPid = MemoryEngine.getAttachedPid()
                    
                    // 如果有保存的 PID 且与当前不同，则重新附加
                    if (savedPid > 0 && currentPid != savedPid) {
                        try {
                            MemoryEngine.attachProcess(savedPid)
                        } catch (e: Exception) {
                            // 附加失败，清除保存的信息
                            prefs.edit().clear().apply()
                        }
                    }
                    
                    result.success(MemoryEngine.getAttachedPid())
                }

                // 内存搜索（全部在后台线程执行）
                "searchExact" -> {
                    val value = call.argument<Any>("value")
                    if (value == null) {
                        result.error("INVALID_VALUE", "Value is required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val results = MemoryEngine.searchExact(value, type)
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SEARCH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "filterResults" -> {
                    val prevAddresses = (call.argument<List<Int>>("previousAddresses") ?: emptyList()).map { it.toLong() }
                    val value = call.argument<Any>("value")
                    if (value == null) {
                        result.error("INVALID_VALUE", "Value is required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val results = MemoryEngine.filterResults(prevAddresses, value, type)
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("FILTER_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "searchByRange" -> {
                    val minValue = call.argument<Number>("minValue")
                    val maxValue = call.argument<Number>("maxValue")
                    if (minValue == null || maxValue == null) {
                        result.error("INVALID_RANGE", "Min and max values are required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val results = MemoryEngine.searchByRange(minValue.toLong(), maxValue.toLong(), type)
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RANGE_SEARCH_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 模糊搜索（未知值搜索）
                "searchFuzzy" -> {
                    val comparison = call.argument<String>("comparison") ?: "changed"
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val results = MemoryEngine.searchFuzzy(comparison, type)
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("FUZZY_SEARCH_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 特征码搜索 (AOB Scan)
                "searchAob" -> {
                    val pattern = call.argument<String>("pattern")
                    if (pattern == null) {
                        result.error("INVALID_PATTERN", "Pattern is required", null)
                        return@setMethodCallHandler
                    }
                    val mask = call.argument<String>("mask")
                    Thread {
                        try {
                            val results = MemoryEngine.searchAob(pattern, mask)
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("AOB_SEARCH_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 特征码重定位（重启后使用）
                "relocateAob" -> {
                    Thread {
                        try {
                            val results = MemoryEngine.relocateAobSignatures()
                            runOnUiThread { result.success(results) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RELOCATE_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 内存读写（全部在后台线程执行）
                "readMemory" -> {
                    val address = call.argument<Int>("address")
                    if (address == null) {
                        result.error("INVALID_ADDRESS", "Address is required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val value = MemoryEngine.readMemory(address, type)
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("READ_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "writeMemory" -> {
                    val address = call.argument<Int>("address")
                    val value = call.argument<Any>("value")
                    if (address == null || value == null) {
                        result.error("INVALID_PARAMS", "Address and value are required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    Thread {
                        try {
                            val success = MemoryEngine.writeMemory(address, value, type)
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("WRITE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "writeBatch" -> {
                    val requests = call.argument<List<Map<String, Any>>>("requests") ?: emptyList()
                    Thread {
                        try {
                            val success = MemoryEngine.writeBatch(requests)
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("BATCH_WRITE_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 内存冻结
                "freezeMemory" -> {
                    val address = call.argument<Int>("address")
                    val value = call.argument<Any>("value")
                    if (address == null || value == null) {
                        result.error("INVALID_PARAMS", "Address and value are required", null)
                        return@setMethodCallHandler
                    }
                    val type = call.argument<String>("type") ?: "dword"
                    try {
                        result.success(MemoryFreezer.freeze(address, value, type))
                    } catch (e: Exception) {
                        result.error("FREEZE_ERROR", e.message, null)
                    }
                }
                "unfreezeMemory" -> {
                    val address = call.argument<Int>("address")
                    if (address == null) {
                        result.error("INVALID_ADDRESS", "Address is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(MemoryFreezer.unfreeze(address))
                    } catch (e: Exception) {
                        result.error("UNFREEZE_ERROR", e.message, null)
                    }
                }
                "getFrozenAddresses" -> {
                    try {
                        result.success(MemoryFreezer.getFrozenAddresses())
                    } catch (e: Exception) {
                        result.error("GET_FROZEN_ERROR", e.message, null)
                    }
                }

                // 内存区域（后台线程执行）
                "getMemoryRegions" -> {
                    Thread {
                        try {
                            val regions = MemoryEngine.getMemoryRegions()
                            runOnUiThread { result.success(regions) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("REGIONS_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "analyzeMemoryRegion" -> {
                    val address = call.argument<Int>("address")
                    if (address == null) {
                        result.error("INVALID_ADDRESS", "Address is required", null)
                        return@setMethodCallHandler
                    }
                    val range = call.argument<Int>("range") ?: 256
                    Thread {
                        try {
                            val analysis = MemoryEngine.analyzeMemoryRegion(address, range)
                            runOnUiThread { result.success(analysis) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ANALYZE_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // Root 权限
                "checkRootAccess" -> {
                    try {
                        result.success(RootManager.checkRootAccess())
                    } catch (e: Exception) {
                        result.error("ROOT_CHECK_ERROR", e.message, null)
                    }
                }
                "requestRootAccess" -> {
                    try {
                        result.success(RootManager.requestRootAccess())
                    } catch (e: Exception) {
                        result.error("ROOT_REQUEST_ERROR", e.message, null)
                    }
                }

                // Native 库状态检查
                "checkNativeStatus" -> {
                    result.success(MemoryEngine.isNativeAvailable())
                }

                // 悬浮窗
                "startOverlay" -> {
                    try {
                        if (canDrawOverlays()) {
                            startOverlayService()
                            result.success(true)
                        } else {
                            requestOverlayPermission()
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("OVERLAY_ERROR", e.message, null)
                    }
                }
                "stopOverlay" -> {
                    try {
                        stopOverlayService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_ERROR", e.message, null)
                    }
                }
                "canDrawOverlays" -> {
                    result.success(canDrawOverlays())
                }

                // 打开 URL
                "openUrl" -> {
                    try {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isNotEmpty()) {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL_ERROR", e.message, null)
                    }
                }

                // 清除悬浮窗保存的聊天记录
                "clearOverlayChats" -> {
                    try {
                        val prefs = getSharedPreferences("gg_overlay_chat", Context.MODE_PRIVATE)
                        prefs.edit().clear().apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_ERROR", e.message, null)
                    }
                }

                // 删除单条悬浮窗聊天记录
                "deleteOverlayChat" -> {
                    try {
                        val sessionId = call.argument<String>("sessionId") ?: ""
                        if (sessionId.isNotEmpty()) {
                            val prefs = getSharedPreferences("gg_overlay_chat", Context.MODE_PRIVATE)
                            prefs.edit().remove(sessionId).apply()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DELETE_ERROR", e.message, null)
                    }
                }

                // 获取悬浮窗保存的脚本运行日志
                "getOverlayScriptLogs" -> {
                    try {
                        val prefs = getSharedPreferences("gg_script_logs", Context.MODE_PRIVATE)
                        val logsJson = prefs.getString("logs", "[]") ?: "[]"
                        val logsArray = org.json.JSONArray(logsJson)
                        val logList = mutableListOf<Map<String, String>>()
                        for (i in 0 until logsArray.length()) {
                            val obj = logsArray.getJSONObject(i)
                            logList.add(mapOf(
                                "name" to obj.optString("name", ""),
                                "scriptName" to obj.optString("scriptName", ""),
                                "time" to obj.optString("time", ""),
                                "output" to obj.optString("output", "")
                            ))
                        }
                        result.success(logList)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }

                // 保存 LLM 配置到 SharedPreferences（供悬浮窗读取）
                "saveLlmConfig" -> {
                    try {
                        val baseUrl = call.argument<String>("baseUrl") ?: ""
                        val apiKey = call.argument<String>("apiKey") ?: ""
                        val model = call.argument<String>("model") ?: "deepseek-chat"
                        val temperature = call.argument<Double>("temperature") ?: 0.7
                        val maxTokens = call.argument<Int>("maxTokens") ?: 4096

                        val json = org.json.JSONObject().apply {
                            put("baseUrl", baseUrl)
                            put("apiKey", apiKey)
                            put("model", model)
                            put("temperature", temperature)
                            put("maxTokens", maxTokens)
                        }

                        val prefs = getSharedPreferences("gg_llm_config", Context.MODE_PRIVATE)
                        prefs.edit().putString("config", json.toString()).apply()

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SAVE_CONFIG_ERROR", e.message, null)
                    }
                }

                // 获取悬浮窗保存的聊天记录
                "getOverlayChats" -> {
                    try {
                        val prefs = getSharedPreferences("gg_overlay_chat", Context.MODE_PRIVATE)
                        val allEntries = prefs.all
                        val chatList = mutableListOf<Map<String, Any>>()

                        for ((key, value) in allEntries) {
                            if (key.startsWith("chat_") && value is String) {
                                try {
                                    val jsonArray = org.json.JSONArray(value)
                                    val messages = mutableListOf<Map<String, Any>>()
                                    for (i in 0 until jsonArray.length()) {
                                        val obj = jsonArray.getJSONObject(i)
                                        val msgMap = mutableMapOf<String, Any>(
                                            "sender" to obj.getString("sender"),
                                            "message" to obj.getString("message")
                                        )
                                        if (obj.has("timestamp")) {
                                            msgMap["timestamp"] = obj.getLong("timestamp")
                                        }
                                        messages.add(msgMap)
                                    }
                                    chatList.add(mapOf(
                                        "id" to key,
                                        "messages" to messages
                                    ))
                                } catch (_: Exception) {}
                            }
                        }

                        result.success(chatList)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }

                // 执行 Lua 脚本
                "executeLuaScript" -> {
                    val scriptId = call.argument<String>("scriptId") ?: ""
                    val scriptContent = call.argument<String>("scriptContent") ?: ""

                    if (scriptContent.isEmpty()) {
                        result.error("EMPTY_SCRIPT", "脚本内容为空", null)
                        return@setMethodCallHandler
                    }

                    // 检查是否已附加进程
                    val pid = MemoryEngine.getAttachedPid()
                    if (pid == null) {
                        result.error("NO_PROCESS", "请先附加游戏进程", null)
                        return@setMethodCallHandler
                    }

                    // 使用 LuaJ 在 JVM 中执行 Lua 脚本
                    Thread {
                        try {
                            LuaEngine.setActivity(this@MainActivity)
                            val output = LuaEngine.executeScript(scriptContent)
                            runOnUiThread { result.success(output) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LUA_ERROR", e.message, null) }
                        }
                    }.start()
                }

                // 同步脚本到 SharedPreferences（供悬浮窗读取）
                "syncScripts" -> {
                    try {
                        val scriptsJson = call.argument<String>("scripts") ?: "[]"
                        val prefs = getSharedPreferences("gg_scripts", Context.MODE_PRIVATE)
                        prefs.edit().putString("scripts", scriptsJson).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC_ERROR", e.message, null)
                    }
                }

                // 同步 Skill 到 SharedPreferences（供悬浮窗读取）
                "syncSkills" -> {
                    try {
                        val skillsJson = call.argument<String>("skills") ?: "[]"
                        val prefs = getSharedPreferences("gg_skills", Context.MODE_PRIVATE)
                        prefs.edit().putString("skills", skillsJson).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC_ERROR", e.message, null)
                    }
                }

                // 导出对话记录到文件
                "exportChatToFile" -> {
                    try {
                        val fileName = call.argument<String>("fileName") ?: "chat_export.md"
                        val content = call.argument<String>("content") ?: ""

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // Android 10+ 使用 MediaStore API
                            val values = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "text/markdown")
                                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Documents/AI-gg")
                            }
                            val uri = contentResolver.insert(
                                android.provider.MediaStore.Files.getContentUri("external"),
                                values
                            )
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { os ->
                                    os.write(content.toByteArray(Charsets.UTF_8))
                                }
                                result.success("Documents/AI-gg/$fileName")
                            } else {
                                result.error("EXPORT_ERROR", "无法创建文件", null)
                            }
                        } else {
                            // Android 9 及以下使用传统方式
                            val externalDir = android.os.Environment.getExternalStorageDirectory()
                            val dir = java.io.File(externalDir, "AI-gg")
                            if (!dir.exists()) dir.mkdirs()

                            val file = java.io.File(dir, fileName)
                            file.writeText(content, Charsets.UTF_8)

                            android.media.MediaScannerConnection.scanFile(
                                this@MainActivity,
                                arrayOf(file.absolutePath),
                                arrayOf("text/markdown"),
                                null
                            )
                            result.success(file.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("EXPORT_ERROR", e.message, null)
                    }
                }

                // 导出 Skill 到文件
                "exportSkillToFile" -> {
                    try {
                        val fileName = call.argument<String>("fileName") ?: "skill.md"
                        val content = call.argument<String>("content") ?: ""

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            // Android 11+ 使用 MediaStore API，路径为 Documents/AI-gg/skills
                            val values = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "text/markdown")
                                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Documents/AI-gg/skills")
                            }
                            val uri = contentResolver.insert(
                                android.provider.MediaStore.Files.getContentUri("external"),
                                values
                            )
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { os ->
                                    os.write(content.toByteArray(Charsets.UTF_8))
                                }
                                result.success("Documents/AI-gg/skills/$fileName")
                            } else {
                                result.error("EXPORT_ERROR", "无法创建文件", null)
                            }
                        } else if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                            // Android 10 使用 MediaStore API，路径为 AI-gg/skills
                            val values = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "text/markdown")
                                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "AI-gg/skills")
                            }
                            val uri = contentResolver.insert(
                                android.provider.MediaStore.Files.getContentUri("external"),
                                values
                            )
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { os ->
                                    os.write(content.toByteArray(Charsets.UTF_8))
                                }
                                result.success("AI-gg/skills/$fileName")
                            } else {
                                result.error("EXPORT_ERROR", "无法创建文件", null)
                            }
                        } else {
                            // Android 9 及以下使用传统方式
                            val externalDir = android.os.Environment.getExternalStorageDirectory()
                            val dir = java.io.File(externalDir, "AI-gg/skills")
                            if (!dir.exists()) dir.mkdirs()

                            val file = java.io.File(dir, fileName)
                            file.writeText(content, Charsets.UTF_8)

                            android.media.MediaScannerConnection.scanFile(
                                this@MainActivity,
                                arrayOf(file.absolutePath),
                                arrayOf("text/markdown"),
                                null
                            )
                            result.success(file.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("EXPORT_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * 通过 Root Shell 执行 Lua 脚本
     * 将脚本写入临时文件，然后通过 luajit 执行
     */
    private fun executeLuaViaShell(scriptContent: String, pid: Int): String {
        return try {
            // 将脚本写入临时文件
            val scriptFile = java.io.File(cacheDir, "temp_script.lua")
            scriptFile.writeText(scriptContent, Charsets.UTF_8)

            // 尝试使用 luajit 执行
            val result = RootManager.executeRootCommand(
                "luajit ${scriptFile.absolutePath} 2>&1"
            )

            // 检查 luajit 是否可用（如果返回 "not found" 或类似错误，回退到直接执行）
            if (result != null && result.isNotEmpty() &&
                !result.contains("not found", ignoreCase = true) &&
                !result.contains("No such file", ignoreCase = true)) {
                result
            } else {
                // luajit 不可用，解析脚本中的关键操作并直接执行
                val directResult = executeScriptDirectly(scriptContent, pid)
                "⚠️ 设备未安装 luajit，使用内置解析器执行：\n\n$directResult"
            }
        } catch (e: Exception) {
            "脚本执行异常: ${e.message}"
        }
    }

    /**
     * 直接解析并执行脚本中的关键操作
     * 当 luajit 不可用时的备用方案
     */
    private fun executeScriptDirectly(scriptContent: String, pid: Int): String {
        val output = StringBuilder()

        try {
            // 解析 gg.searchNumber 调用
            val searchPattern = Regex("""gg\.searchNumber\((.+?),\s*(.+?)\)""")
            for (match in searchPattern.findAll(scriptContent)) {
                val value = match.groupValues[1].trim().removeSurrounding("\"").removeSurrounding("'")
                val typeStr = match.groupValues[2].trim()

                val type = when {
                    typeStr.contains("DWORD") -> "dword"
                    typeStr.contains("FLOAT") -> "float"
                    typeStr.contains("DOUBLE") -> "double"
                    typeStr.contains("BYTE") -> "byte"
                    typeStr.contains("WORD") -> "word"
                    typeStr.contains("QWORD") -> "qword"
                    else -> "dword"
                }

                val numValue: Any = when (type) {
                    "float", "double" -> value.toDoubleOrNull() ?: 0.0
                    else -> value.toLongOrNull() ?: 0
                }

                val results = MemoryEngine.searchExact(numValue, type)
                output.appendLine("搜索 $value ($type): 找到 ${results.size} 个结果")

                for (r in results.take(10)) {
                    output.appendLine("  ${r["address"]} = ${r["value"]}")
                }
                if (results.size > 10) {
                    output.appendLine("  ... 还有 ${results.size - 10} 个结果")
                }
            }

            // 解析 gg.writeMemory 调用
            val writePattern = Regex("""gg\.writeMemory\((.+?),\s*(.+?),\s*(.+?)\)""")
            for (match in writePattern.findAll(scriptContent)) {
                val addrStr = match.groupValues[1].trim()
                val valueStr = match.groupValues[2].trim().removeSurrounding("\"").removeSurrounding("'")
                val typeStr = match.groupValues[3].trim()

                val type = when {
                    typeStr.contains("DWORD") -> "dword"
                    typeStr.contains("FLOAT") -> "float"
                    typeStr.contains("DOUBLE") -> "double"
                    else -> "dword"
                }

                val address = addrStr.toLongOrNull(16)?.toInt() ?: continue
                val value: Any = when (type) {
                    "float", "double" -> valueStr.toDoubleOrNull() ?: 0.0
                    else -> valueStr.toLongOrNull() ?: 0
                }

                val success = MemoryEngine.writeMemory(address, value, type)
                output.appendLine("写入 ${addrStr} = $value ($type): ${if (success) "成功" else "失败"}")
            }

            // 解析 gg.toast 调用
            val toastPattern = Regex("""gg\.toast\(["'](.+?)["']\)""")
            for (match in toastPattern.findAll(scriptContent)) {
                output.appendLine("📢 ${match.groupValues[1]}")
            }

            if (output.isEmpty()) {
                output.appendLine("脚本已解析，但未找到可直接执行的操作。")
                output.appendLine("提示：请确保设备已安装 luajit 以执行完整 Lua 脚本。")
            }
        } catch (e: Exception) {
            output.appendLine("脚本解析异常: ${e.message}")
        }

        return output.toString()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel.setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val page = intent.getStringExtra("page")
        if (page != null) {
            pendingPage = page
            // 延迟通知 Flutter 端，确保 channel 就绪
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    if (::channel.isInitialized) {
                        channel.invokeMethod("onNavigate", page)
                    }
                } catch (_: Exception) {}
            }, 300)
        }
    }

    // ==================== 权限管理 ====================

    /**
     * 首次启动时申请所有必要权限
     */
    private fun requestAllPermissionsOnFirstLaunch() {
        val prefs = getSharedPreferences("gg_permissions", Context.MODE_PRIVATE)
        val isFirstLaunch = prefs.getBoolean("is_first_launch", true)

        if (isFirstLaunch) {
            prefs.edit().putBoolean("is_first_launch", false).apply()

            // 延迟执行，确保 Flutter 引擎就绪
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                requestStoragePermissions()
                requestOverlayPermission()
            }, 1000)
        }
    }

    /**
     * 申请存储权限
     */
    private fun requestStoragePermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ 使用细粒度媒体权限
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_VIDEO)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_MEDIA_AUDIO)
            }
        } else {
            // Android 12 及以下使用传统存储权限
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissions.toTypedArray(),
                STORAGE_PERMISSION_REQUEST
            )
        }
    }

    /**
     * 申请悬浮窗权限
     */
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
            }
        }
    }

    /**
     * 权限申请结果回调
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            STORAGE_PERMISSION_REQUEST -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (allGranted) {
                    // 存储权限已授予
                }
            }
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun startOverlayService() {
        val intent = Intent(this, OverlayService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopOverlayService() {
        val intent = Intent(this, OverlayService::class.java)
        stopService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OVERLAY_PERMISSION_REQUEST) {
            if (canDrawOverlays()) {
                startOverlayService()
            }
        }
    }
}
