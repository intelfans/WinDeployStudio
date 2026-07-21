/// Provider-independent output policy for the in-app deployment assistant.
///
/// Responses are screened after the complete stream has been buffered so an
/// incompatible or untrusted endpoint cannot flash disallowed content before
/// the client has evaluated it.
class AiOutputSafetyFilter {
  AiOutputSafetyFilter._();

  static final List<RegExp> _blockedPatterns = <RegExp>[
    // Politics and political advocacy.
    RegExp(
      r'\b(?:politics?|political|elections?|electoral|presidents?|prime ministers?|parliament|congress|democrats?|republicans?|governments?|geopolitics?|politische|politik|élections?|politique|elecciones?|política|eleições?|política)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:政治|政党|政黨|选举|選舉|总统|總統|总理|總理|议会|議會|国会|國會|政府|地缘政治|地緣政治|정치|선거|대통령|정부|選挙|大統領|политик|выбор|президент|правительств|سياس|انتخاب|حكوم)',
      caseSensitive: false,
      unicode: true,
    ),

    // Sexual or pornographic material.
    RegExp(
      r'\b(?:porn(?:ography)?|porno|sex|sexual(?:ly)?|sexuell|nude|nudity|naked|erotic|fetish|genitals?|rape|incest|prostitut(?:e|ion)|xxx)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:色情|成人内容|成人內容|性行为|性行為|性交|裸体|裸體|淫秽|淫穢|强奸|強姦|乱伦|亂倫|卖淫|賣淫|生殖器|포르노|성행위|나체|강간|ポルノ|性行為|裸体|強姦|порн|эрот|изнасил|إباح|جنس|اغتصاب)',
      caseSensitive: false,
      unicode: true,
    ),

    // Violence, self-harm, weapons, and extremist harm.
    RegExp(
      r'\b(?:violence|violent|murder(?:er|ing|ed)?|assault|torture|weapons?|bomb(?:ing|s)?|explosives?|shoot(?:ing)?|stabb(?:ing|ed)|suicide|self[- ]harm|terrorism|terrorist|massacre|behead(?:ing)?|warfare|genocide)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'\bkill(?:ing|ed)?\s+(?:(?:a|an|the)\s+)?(?:people|person|someone|human|civilian|child|children|him|her|them)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:杀人|殺人|杀害|殺害|谋杀|謀殺|暴力|武器|炸弹|炸彈|爆炸物|枪击|槍擊|刺杀|刺殺|自杀|自殺|自残|自殘|恐怖袭击|恐怖襲擊|屠杀|屠殺|战争|戰爭|폭력|무기|폭탄|총격|자살|테러|暴力|武器|爆弾|銃撃|自殺|テロ|насили|оруж|бомб|самоуб|террор|عنف|سلاح|قنبلة|انتحار|إرهاب)',
      caseSensitive: false,
      unicode: true,
    ),

    // Hate, illegal drugs, gambling, and explicit criminal facilitation.
    RegExp(
      r'\b(?:hate speech|racial supremacy|ethnic cleansing|extremist recruitment|cocaine|heroin|methamphetamine|fentanyl|illegal drugs?|narcotics?|drug manufacture|gambling|casino|betting|wagering)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:仇恨言论|仇恨言論|种族至上|種族至上|极端主义|極端主義|毒品|可卡因|海洛因|冰毒|赌博|賭博|赌场|賭場|증오 발언|마약|도박|ヘイトスピーチ|麻薬|賭博|наркот|азартн|خطاب كراهية|مخدر|قمار)',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'\b(?:how to hack|create malware|write ransomware|steal passwords?|bypass authentication)\b',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'(?:制作恶意软件|製作惡意軟體|编写勒索软件|編寫勒索軟體|窃取密码|竊取密碼|绕过身份验证|繞過身分驗證)',
      caseSensitive: false,
      unicode: true,
    ),
  ];

  static bool blocks(String text) {
    if (text.trim().isEmpty) return false;
    return _blockedPatterns.any((pattern) => pattern.hasMatch(text));
  }

  static bool blocksAny(Iterable<String> values) =>
      values.any((value) => blocks(value));
}
