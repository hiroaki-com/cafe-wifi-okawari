// メニューバーに cafe-wifi-okawari の状態を出す（DESIGN.md §3.2）。表示するだけで、判定はすべて同じ場所の .sh が行う。
// 起動: osascript -l JavaScript <この .js>。--check を付けると、アイコンとメニューを1回作って終わる（CI での読み込みの確認用）
ObjC.import('Cocoa')

const sa = Application.currentApplication()
sa.includeStandardAdditions = true
// 自分のパス（osascript の引数）の .js を .sh に替えたものが判定のスクリプト（導入先でもリポジトリでも同じ名前の組）
const self = $.NSURL.fileURLWithPath(ObjC.deepUnwrap($.NSProcessInfo.processInfo.arguments).find(a => a.endsWith('.js'))).path.js
const SH = self.replace(/\.js$/, '.sh')
const LOG = $.NSHomeDirectory().js + '/Library/Logs/cafe-wifi-okawari.log'
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

function refresh() {
  let out = ['off']
  try { out = sa.doShellScript("/bin/zsh '" + SH.replace(/'/g, "'\\''") + "'", { alteringLineEndings: false }).replace(/\n$/, '').split('\n') } catch (e) {}
  const k = MARK.hasOwnProperty(out[0]) ? out[0] : 'off'
  item.button.appearsDisabled = k === 'off'
  item.button.title = MARK[k]

  menu.removeAllItems
  for (const l of out.slice(1)) {
    if (!l) { menu.addItem($.NSMenuItem.separatorItem); continue }
    const [kind, text, right, tip] = l.split('\t')
    if (kind === 'head') { menu.addItem($.NSMenuItem.sectionHeaderWithTitle(text)); continue }   // macOS 14 以降
    const m = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(right ? text + '\t' + right : text, null, '')
    if (right) {
      // alloc の直後では initWithString:attributes: が橋渡しされない（macOS 27）ので、new で作って中身と属性を入れる
      const s = $.NSMutableAttributedString.new
      s.replaceCharactersInRangeWithString($.NSMakeRange(0, 0), m.title)
      s.setAttributesRange(cols, $.NSMakeRange(0, s.length))
      m.attributedTitle = s
    }
    m.image = DOT.hasOwnProperty(kind) ? DOT[kind] : BLANK   // 色以外の種類（-）は印なし
    if (tip) m.toolTip = tip
    m.enabled = false   // 状態と案内の行は押せない
    menu.addItem(m)
  }
  menu.addItem($.NSMenuItem.separatorItem)
  const open = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Open Log', 'openLog:', '')
  open.target = handler
  open.enabled = $.NSFileManager.defaultManager.fileExistsAtPath(LOG)
  menu.addItem(open)
  // 終了するだけ（KeepAlive なしなので、次のログインか install.sh で戻る）
  const hide = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent('Hide from Menu Bar', 'terminate:', '')
  hide.target = app
  menu.addItem(hide)
}

ObjC.registerSubclass({
  name: 'OkawariMenubar',
  protocols: ['NSMenuDelegate'],
  methods: {
    'tick:': { types: ['void', ['id']], implementation: () => refresh() },
    'menuNeedsUpdate:': { types: ['void', ['id']], implementation: () => refresh() },   // メニューを開く直前
    'openLog:': { types: ['void', ['id']], implementation: () => $.NSWorkspace.sharedWorkspace.openURL($.NSURL.fileURLWithPath(LOG)) },
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
