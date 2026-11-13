// メニューバーに cafe-wifi-okawari の状態を出す（DESIGN.md §3.2）。表示するだけで、判定はすべて同じ場所の .sh が行う。
// 起動: osascript -l JavaScript <この .js>。--check を付けると、アイコンとメニューを1回作って終わる（CI での読み込みの確認用）
ObjC.import('Cocoa')

const sa = Application.currentApplication()
sa.includeStandardAdditions = true
// 自分のパス（osascript の引数）の .js を .sh に替えたものが判定のスクリプト（導入先でもリポジトリでも同じ名前の組）
const self = $.NSURL.fileURLWithPath(ObjC.deepUnwrap($.NSProcessInfo.processInfo.arguments).find(a => a.endsWith('.js'))).path.js
const SH = self.replace(/\.js$/, '.sh')
const LOG = $.NSHomeDirectory().js + '/Library/Logs/cafe-wifi-okawari.log'
// Check Now の要求ファイル（netcheck.sh の LaunchAgent が WatchPaths で見ている。DESIGN.md §3.3）
const REQ = $.NSHomeDirectory().js + '/Library/Caches/cafe-wifi-okawari.netcheck.now'
// 危険の記録（netcheck.sh が足す）。あれば Dismiss Network Warning を出し、押すと消す（⚠ はそれまで残る）
const ALERT = $.NSHomeDirectory().js + '/Library/Caches/cafe-wifi-okawari.netcheck.alert'
// Uninstall… で実行する install.sh の複製（導入したときだけある。リポジトリから動かしたときは押せない）
const CTL = $.NSHomeDirectory().js + '/.local/bin/cafe-wifi-okawari-ctl'
// アイコンの素材（1x・2x の組）。導入先では .js と同じ名前の .png・@2x.png、リポジトリでは assets/icon の素材
const ICON = [self.replace(/\.js$/, ''), self.replace(/[^/]*$/, 'assets/icon/menuBarTemplate')].find(p => $.NSFileManager.defaultManager.fileExistsAtPath(p + '.png'))
// アイコンの種類ごとの印。これ以外の値と実行の失敗は off として扱う
const MARK = { off: '', warn: ' !', wait: ' …', check: ' ✓', on: '' }

const app = $.NSApplication.sharedApplication
app.setActivationPolicy($.NSApplicationActivationPolicyAccessory)   // Dock に出さない
const item = $.NSStatusBar.systemStatusBar.statusItemWithLength($.NSVariableStatusItemLength)
// 1x・2x を同じ 18 × 18 pt の画像の表現にする（assets/icon/README.md）。どちらかが読めなければ起動しない（--check も失敗する）
const img = $.NSImage.alloc.initWithSize($.NSMakeSize(18, 18))
for (const f of [ICON + '.png', ICON + '@2x.png']) {
  const r = $.NSImageRep.imageRepWithContentsOfFile(f)
  if (r.isNil()) throw new Error('cannot read the icon: ' + f)
  r.size = $.NSMakeSize(18, 18)
  img.addRepresentation(r)
}
img.template = true   // ライト・ダーク・色付きのメニューバーに合わせて色が変わる（ファイル名での判定には頼らない）
img.accessibilityDescription = 'cafe-wifi-okawari'
item.button.image = img
const menu = $.NSMenu.alloc.init
item.menu = menu

// 行の左の印（AppKit 標準の状態の画像）と、印のない行の文字を印のある行にそろえる透明な画像
const D = 12
function dot(name) { const i = $.NSImage.imageNamed(name).copy; i.size = $.NSMakeSize(D, D); return i }
const DOT = { green: dot($.NSImageNameStatusAvailable), yellow: dot($.NSImageNameStatusPartiallyAvailable),
  red: dot($.NSImageNameStatusUnavailable), gray: dot($.NSImageNameStatusNone) }
const BLANK = $.NSImage.alloc.initWithSize($.NSMakeSize(D, D))

// 右の列（直近の出来事の中身・次の時間切れの時刻）をそろえるタブ位置
const ps = $.NSMutableParagraphStyle.alloc.init
ps.tabStops = $([$.NSTextTab.alloc.initWithTextAlignmentLocationOptions($.NSTextAlignmentLeft, 110, $())])
const cols = $.NSDictionary.dictionaryWithObjectsForKeys(
  $([$.NSFont.menuFontOfSize(0), ps, $.NSColor.disabledControlTextColor]),
  $([$.NSFontAttributeName, $.NSParagraphStyleAttributeName, $.NSForegroundColorAttributeName]))

// 1行を m（メニューかサブメニュー）に足す。状態の行は押せない行として足し、その項目を返す（見出し・区切り線は null）
function add(m, l) {
  if (!l) { m.addItem($.NSMenuItem.separatorItem); return null }
  const [kind, text, right, tip] = l.split('\t')
  if (kind === 'head') { m.addItem($.NSMenuItem.sectionHeaderWithTitle(text)); return null }   // macOS 14 以降
  const i = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(right ? text + '\t' + right : text, null, '')
  if (right) {
    // alloc の直後では initWithString:attributes: が橋渡しされない（macOS 27）ので、new で作って中身と属性を入れる
    const s = $.NSMutableAttributedString.new
    s.replaceCharactersInRangeWithString($.NSMakeRange(0, 0), i.title)
    s.setAttributesRange(cols, $.NSMakeRange(0, s.length))
    i.attributedTitle = s
  }
  i.image = DOT.hasOwnProperty(kind) ? DOT[kind] : BLANK   // 色以外の種類（-）は印なし
  if (tip) i.toolTip = tip
  i.enabled = false   // 状態と案内の行は押せない
  m.addItem(i)
  return i
}

function refresh() {
  let out = ['off']
  try { out = sa.doShellScript("/bin/zsh '" + SH.replace(/'/g, "'\\''") + "'", { alteringLineEndings: false }).replace(/\n$/, '').split('\n') } catch (e) {}
  const [k0, risk] = out[0].split(' ')
  const k = MARK.hasOwnProperty(k0) ? k0 : 'off'
  item.button.appearsDisabled = k === 'off'
  item.button.title = risk === 'risk' ? (MARK[k] || ' ') + '⚠' : MARK[k]   // ネットワークの診断の危険（例: ✓⚠）

  menu.removeAllItems
  // > で始まる行は、直前の > のない行のサブメニューの行。サブメニューを持つ行だけを押せる（開ける）項目にする
  let parent = null, sub = null
  const subs = []
  for (const l of out.slice(1)) {
    if (!l.startsWith('>')) { parent = add(menu, l); sub = null; continue }
    if (!parent) continue
    if (!sub) { sub = $.NSMenu.alloc.init; sub.autoenablesItems = false; parent.submenu = sub; parent.enabled = true; subs.push(sub) }
    add(sub, l.slice(1))
  }
  // サブメニューの末尾の操作（今はネットワークの診断だけ）。押すと要求ファイルを作り、診断の LaunchAgent がすぐ動く
  for (const m of subs) {
    m.addItem($.NSMenuItem.separatorItem)
    const now = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Check Now', 'checkNow:', '')
    now.target = handler
    m.addItem(now)
  }
  menu.addItem($.NSMenuItem.separatorItem)
  if ($.NSFileManager.defaultManager.fileExistsAtPath(ALERT)) {
    const dis = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Dismiss Network Warning', 'dismiss:', '')
    dis.target = handler
    menu.addItem(dis)
  }
  const open = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Open Log', 'openLog:', '')
  open.target = handler
  open.enabled = $.NSFileManager.defaultManager.fileExistsAtPath(LOG)
  menu.addItem(open)
  // 終了するだけ（KeepAlive なしなので、次のログインか install.sh で戻る）
  const hide = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Hide from Menu Bar', 'terminate:', '')
  hide.target = app
  menu.addItem(hide)
  menu.addItem($.NSMenuItem.separatorItem)
  const un = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Uninstall…', 'uninstall:', '')
  un.target = handler
  un.enabled = $.NSFileManager.defaultManager.fileExistsAtPath(CTL)
  menu.addItem(un)
}

// Uninstall… の確認。削除するもの・残すログの場所を示し、既定のボタン（Return）は Cancel にする
function confirmUninstall() {
  const a = $.NSAlert.alloc.init
  a.alertStyle = $.NSAlertStyleWarning
  a.messageText = 'Uninstall cafe-wifi-okawari?'
  a.informativeText = 'Automatic re-authentication stops, and the menu bar icon, the network check and the list of accepted networks are removed.' +
    '\n\nThe log is kept: ~/Library/Logs/cafe-wifi-okawari.log (delete it by hand if you no longer need it).'
  const un = a.addButtonWithTitle('Uninstall')
  un.hasDestructiveAction = true
  un.keyEquivalent = ''
  a.addButtonWithTitle('Cancel').keyEquivalent = '\r'
  app.activate
  return a.runModal === $.NSAlertFirstButtonReturn
}
// 削除は install.sh の複製の uninstall に任せる。uninstall はメニューバーの登録を最後に外し、そこでこのプロセスも終わる
// （launchd がジョブのプロセスをまとめて終わらせる）。戻ってきても -ctl が消えていれば削除はできている（launchd の外で
// 動かしたときなど）ので、メニューバーを終える。-ctl が残っていれば削除に失敗しているので、ターミナルでの方法を示す
function uninstall() {
  if (!confirmUninstall()) return
  try { sa.doShellScript("/bin/zsh '" + CTL.replace(/'/g, "'\\''") + "' uninstall") } catch (e) {}
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(CTL)) { app.terminate(null); return }
  const a = $.NSAlert.alloc.init
  a.alertStyle = $.NSAlertStyleCritical
  a.messageText = 'Could not uninstall cafe-wifi-okawari'
  a.informativeText = 'Run this in Terminal:\nzsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall'
  app.activate
  a.runModal
}

ObjC.registerSubclass({
  name: 'OkawariMenubar',
  protocols: ['NSMenuDelegate'],
  methods: {
    'tick:': { types: ['void', ['id']], implementation: () => refresh() },
    'menuNeedsUpdate:': { types: ['void', ['id']], implementation: () => refresh() },   // メニューを開く直前
    'openLog:': { types: ['void', ['id']], implementation: () => $.NSWorkspace.sharedWorkspace.openURL($.NSURL.fileURLWithPath(LOG)) },
    // シェルを呼ばずに空の要求ファイルを作る（中身は読まれない）
    'dismiss:': { types: ['void', ['id']], implementation: () => { $.NSFileManager.defaultManager.removeItemAtPathError(ALERT, null); refresh() } },
    'checkNow:': { types: ['void', ['id']], implementation: () => $.NSFileManager.defaultManager.createFileAtPathContentsAttributes(REQ, $.NSData.data, $.NSDictionary.dictionary) },
    'uninstall:': { types: ['void', ['id']], implementation: () => uninstall() },
  },
})
const handler = $.OkawariMenubar.alloc.init
menu.autoenablesItems = false
menu.delegate = handler

function run(argv) {
  refresh()
  if (argv[0] === '--check') return 'ok: ' + item.button.title.js + ' ' + menu.numberOfItems + ' items'
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(10, handler, 'tick:', null, true)
  app.run
}
