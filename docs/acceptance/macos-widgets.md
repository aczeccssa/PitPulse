# macOS 原生 Widget 与共享实现验收

## 范围

- 三类普通 Widget（下一场、比赛周末、F1 计时）共用 `Shared/Widgets/RaceWidgets.swift` 的布局、Widget 定义和 TimelineProvider，Mac 支持小/中/大；iOS 继续保留锁屏尺寸。
- iOS ActivityKit / Dynamic Island 保留在原 iOS 扩展文件，不进入 Mac 编译。
- 不新增 Swift Package：共享 Widget 源文件通过 Xcode target membership 编译到两端扩展及 iOS DEBUG 预览；既有 Shared/Data/Components 分层不变。
- `WidgetSnapshotPublisher` 只编译到 App 和测试。两端扩展只读 Shared 缓存，不链接网络栈，不持有 Token，也不直连 Provider。
- Mac App 使用现有 LiveStore（当前选择 F1 时）发布 F1 快照；切到 WEC 清除 F1 timing 缓存，不额外开一个后台 F1 连接。

## 本机共享缓存与刷新语义

- iOS 保留原 `group.com.pitpulse.mobile`，不迁移现有安装数据。
- Mac host 与 sandboxed extension 共用 Team-prefixed group `9RQST8G2LS.com.pitpulse.widgets`。这只共享同一台 Mac 的 App/扩展数据，不跨设备同步；Mac host 保持原非 sandbox 行为，避免影响既有 Keychain、网络与本地缓存。
- Live 正常更新至多每 30 秒请求一次 timeline reload；会话/状态变化立即发布。断线保留旧值但立即标 stale，换服务器/赛季或删除凭证清缓存；切换 Live 数据源清 timing 缓存。
- 延用缓存原始年龄；服务端 stale 不重新标记为新鲜。计时保留原始 updatedAt、回放标识、90 秒过期判断；无时间戳按过期处理。
- Widget timeline 安排赛历六小时过期和计时过期条目；系统决定实际刷新预算，reload 请求不是即时渲染保证。App 退出后不继续联网，可能显示上次快照并过期；这不是后台实时计时服务。
- Mac Widget 使用独立 `pitpulse-desktop` scheme，避免同机 iOS App 抢走通用 scheme。赛历打开复用 CalendarView 的窗口；Live 打开已有 Live Island 并选择 F1，不创建第二个 Live 窗口。

## 已观察的构建与回归

- Taskdeck `Build App Release`：最终源码 exit 0，包含已签名并嵌入的 Mac Widget Extension；`Build App` 首轮 Debug 构建也通过。
- Taskdeck `Build App Tests`：exit 0，编译原 Mac App/XCTest 与新增共享 publisher 测试，未运行 App test host。
- Taskdeck `Build iOS`：exit 0，含 iOS 扩展与原 DEBUG 同源预览入口。
- Taskdeck `Test iOS`：16 tests / 0 failures（原 12 项 + 共享发布器/路由 4 项）。最终源码复跑结果记录在任务 JSON。
- Taskdeck `Check Widget Publisher`：通过 4 项生产发布器 XCTest，独立 xctest bundle，不启动/停止 PitPulse。
- Release App 与内嵌扩展 `codesign --verify --deep --strict` 通过；两者签名 entitlement 中 group 一致，扩展启用 sandbox。
- `plutil -lint` 工程及新 plist/entitlements 通过；`git diff --check` 通过。

Headless XCTest 覆盖赛历旧缓存年龄/取消场次/空列表、Live 节流、会话/状态立即刷新、断线与回放、缺时间戳、WEC 隔离、清理和合法深链接。第一次独立 XCTest 链接失败是检查脚本缺少 XCTestSwiftSupport 路径，修正后复跑通过，不视为产品测试通过之前的证据。

## 尚未验收（不得用构建代替）

- 初轮交付没有替换运行实例。后续用户要求更新 Run App 后，已修正启动时机、通过新版启动链运行 Release App，并完成 LaunchServices/PlugInKit 注册命令；服务器保持原进程。PlugInKit 查询权限受限，不能由注册命令成功推断组件图库已可见。
- 真正 macOS 桌面/通知中心添加三类 Widget 的小/中/大尺寸、浅深色、跨进程 App Group 实际读取及点击路由仍需运行新版做系统验收。
- 未进行签名 iPhone / 后台持续 Live Activity 验收，T26/T27 原缺口保持。
- Release 构建及最终回归均已完成；系统添加验收前 T28 不标 done。

签名方案核验：尝试直接复用 iOS 的 `group.com.pitpulse.mobile` 后，Mac 构建要求新增对应 App/Extension provisioning profiles 并失败；未自动修改开发者账户或生成 profiles，恢复 Team-prefixed Mac group 后，最终 Release 和 build-for-testing 均 exit 0。

## App 内 Widget 横滑陈列预览

按用户提供的系统组件选择器截图改造既有 iOS DEBUG 预览入口（设置 → 组件 → 预览组件尺寸与外观）。三类组件各小/中/大共九页，使用原生水平 ScrollView、viewAligned 吸附与 scrollPosition 同步页码；保留两侧边距和相邻页露出。标题、说明、尺寸和可点击分页圆点跟随当前页。预览按组件原生比例缩放，不拉伸共享 Widget 布局；继续读取真实 App Group 缓存，不加入样例赛事。

提供系统/浅色/深色外观，打开后立即读取缓存并每 15 秒自动重读；退到后台或关闭预览时取消刷新任务。工具栏 info.circle 提供原「如何添加小组件」指引，移除手动刷新、大号添加指引按钮和底部「预览读取 App…」文字。预览从设置单独弹出新的 large sheet，带关闭按钮，不在设置 NavigationStack 内推入。纵向固定布局，仅保留水平组件滚动；组件区域按剩余高度缩放。按各组件实际展示宽度排列、间距 10pt（含每项 8pt 余量），不再给小组件套整页空白。分页圆点中心距 14pt，垂直点击区域 44pt；另保留 VoiceOver 调整动作。静态轻微 X/Y/Z 旋转和 Y 偏移营造陈列透视，开启减少动态效果时取消倾斜与程序切页动画。

本轮 Build iOS exit 0；最终回归结果记录在 T28。开始验证时没有已启动模拟器，尚未对横滑手势、动态字体、九页截图和参考图逐帧进行实际 UI 验收；编译及单元测试不能替代这些视觉验收。Mac 运行实例和服务器未改动。


## 后续间距与设置层级修正

用户指出实际宽度紧贴排列过密后，恢复等宽分页槽（视口减64pt）、12pt页间距和32pt两侧边距；组件最大宽度为视口减120pt，在槽内保留明确留白，不再按组件实际宽度紧贴排列。保留轻微三轴倾斜、独立sheet及15秒缓存重读。预览删除色彩模式控件和私有外观状态，直接使用继承外观。预览与设置关闭/信息toolbar显式Image图标，不依赖系统对文字Label的自动折叠。

设置统一原生grouped Form与分组背景、红色主强调；服务器地址/令牌均为带标题和一致内边距/背景的输入，保存为唯一填充主按钮，检查连接为次级图标按钮；赛季/主题/车手收进偏好，灵动岛、组件入口、关于分组明确。主题使用与其他偏好一致的菜单选择，避免混用分段/列表风格。保留原保存地址/Token和检查连接业务行为。

本轮实际视觉、不同屏幕和动态字体仍待设备验收；仅编译与回归结果记入任务证据，不宣称与参考图完全一致。

## 服务器入口与统一组件区修正

设置主列表中的「服务器」现在是单行摘要：当前 URL 可点击打开，旁边显示连接成功/失败/未检查状态图标，仅提供配置入口。配置入口打开独立大尺寸 sheet，顶部大号服务器图标与标题，中间服务器地址和可选 Token 两个输入，下方仅提供「测试」「保存」操作；测试实际调用 health API 并展示结果，编辑任一输入会清除旧测试结论，测试时禁用保存以避免验证和提交对象不一致。空 Token 在当前地址下保留已有 Keychain token；改地址空 Token 走无凭证测试；保存仍走既有 Keychain 逻辑。

组件设置区聚合灵动岛与桌面组件：灵动岛使用系统 Picker 的左侧文字/右侧选项布局；桌面组件预览为纯文字入口，删除装饰图标和手画箭头。桌面预览保持原生组件实际尺寸，分页间距 16pt 且仅轻微收窄，保留两侧露出。

Build iOS exit 0；最终 Test iOS 结果记录在任务 JSON。设备端地址链接、status 更新、Token 保留和 sheet 手势尚未实际操作验收。

## 最终提交口径（PP-45）

以上各节记录迭代过程；最终实现以源码和本节为准：预览使用原生尺寸（无 scaleEffect）、16pt分页间距、独立根节点sheet、15秒前台缓存重读，已移除预览主题选择。服务器sheet当前使用居中标题/描述和两个输入、测试/保存，主设置为地址链接/健康状态/编辑入口。用户直接调整的排版保留，不重新引入已移除的图标或说明。

首次服务器sheet瞬开瞬关：两个子sheet已从Form行/Section移到稳定Settings根视图。这是基于代码生命周期的针对性修正，未在设备上复现和证明根因，首次点击复验仍为开放项。提交前对最终源码重新执行Test iOS，exit 0，16 tests / 0 failures。构建/单元测试不覆盖这一原生交互缺口。

跟踪：PP-45（T28），关联PP-40、PP-41。时间记录采用真实UTC `updatedAt` 和Asia/Shanghai说明；YouTrack现有schema未提供自定义开始/完成日期，不为未完成验收填写完成日期，不按会话跨度虚报工时。
