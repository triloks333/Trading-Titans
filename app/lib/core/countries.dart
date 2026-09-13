/// Country and subdivision lists for the self-declared location question.
///
/// Backs the country/state pickers in Settings. The answer is sent to
/// `save_user_preferences`, which uppercases the code and derives
/// `profiles.location` from it — 'IN' means india, anything else means
/// outside_india. That derived flag is what decides the billing currency, so a
/// code that is not real ISO 3166-1 alpha-2 is a money bug, not a cosmetic one.
/// Hence the shape check in `preferences_test.dart` mirrors the database's
/// `^[A-Z]{2}$` constraint rather than trusting the data by eye.
///
/// The data is packed `CC=Name;CC=Name` strings parsed once on first use, not a
/// 250-entry map literal: it is only ever read as a whole list (a picker) or by
/// key, so a literal would be 250 lines of source no reader benefits from.
library;

class Countries {
  Countries._();

  static Map<String, String>? _byCode;

  /// Country name by ISO 3166-1 alpha-2 code, uppercase.
  static Map<String, String> get byCode => _byCode ??= Map.unmodifiable({
        for (final chunk in _kPacked)
          for (final pair in chunk.split(';'))
            pair.substring(0, 2): pair.substring(3),
      });

  static List<MapEntry<String, String>>? _byName;

  /// Every country, sorted by name, ready to drop into a picker.
  static List<MapEntry<String, String>> get sortedByName =>
      _byName ??= List.unmodifiable(byCode.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value)));

  /// The display name for a code, or null when it is not a country we know.
  /// Tolerates lowercase and stray whitespace, the same way the RPC does.
  static String? name(String? code) =>
      code == null ? null : byCode[code.trim().toUpperCase()];

  static List<String>? _india;

  /// India's 28 states and 8 union territories, alphabetical in one list. The
  /// constitutional distinction is not something a user picking their own state
  /// needs to navigate.
  static List<String> get indiaSubdivisions =>
      _india ??= List.unmodifiable(_kIndiaSubdivisions.split(';'));

  /// The subdivisions we ship a list for. Empty means "let the user type it".
  ///
  /// ponytail: only India is enumerated, because it is 242 of 316 accounts and
  /// the column is free text server-side, capped at 80 characters. Adding another
  /// country means one more packed string and one more case here — no migration.
  static List<String> subdivisionsOf(String? code) =>
      code?.trim().toUpperCase() == 'IN' ? indiaSubdivisions : const [];
}

// ── Packed data ────────────────────────────────────────────────────────────
// Split by leading letter purely so each constant stays a readable length.
const List<String> _kPacked = [
  _kAB,
  _kCD,
  _kEG,
  _kHK,
  _kLM,
  _kNP,
  _kQS,
  _kTZ,
];

const _kAB =
    "AD=Andorra;AE=United Arab Emirates;AF=Afghanistan;AG=Antigua and Barbuda;"
    "AI=Anguilla;AL=Albania;AM=Armenia;AO=Angola;AQ=Antarctica;AR=Argentina;"
    "AS=American Samoa;AT=Austria;AU=Australia;AW=Aruba;AX=Åland Islands;"
    "AZ=Azerbaijan;BA=Bosnia and Herzegovina;BB=Barbados;BD=Bangladesh;"
    "BE=Belgium;BF=Burkina Faso;BG=Bulgaria;BH=Bahrain;BI=Burundi;BJ=Benin;"
    "BL=Saint Barthélemy;BM=Bermuda;BN=Brunei Darussalam;BO=Bolivia;"
    "BQ=Bonaire, Sint Eustatius and Saba;BR=Brazil;BS=Bahamas;BT=Bhutan;"
    "BV=Bouvet Island;BW=Botswana;BY=Belarus;BZ=Belize";

const _kCD =
    "CA=Canada;CC=Cocos (Keeling) Islands;CD=Congo (Kinshasa);"
    "CF=Central African Republic;CG=Congo (Brazzaville);CH=Switzerland;"
    "CI=Côte d'Ivoire;CK=Cook Islands;CL=Chile;CM=Cameroon;CN=China;"
    "CO=Colombia;CR=Costa Rica;CU=Cuba;CV=Cabo Verde;CW=Curaçao;"
    "CX=Christmas Island;CY=Cyprus;CZ=Czechia;DE=Germany;DJ=Djibouti;"
    "DK=Denmark;DM=Dominica;DO=Dominican Republic;DZ=Algeria";

const _kEG =
    "EC=Ecuador;EE=Estonia;EG=Egypt;EH=Western Sahara;ER=Eritrea;ES=Spain;"
    "ET=Ethiopia;FI=Finland;FJ=Fiji;FK=Falkland Islands;FM=Micronesia;"
    "FO=Faroe Islands;FR=France;GA=Gabon;GB=United Kingdom;GD=Grenada;"
    "GE=Georgia;GF=French Guiana;GG=Guernsey;GH=Ghana;GI=Gibraltar;"
    "GL=Greenland;GM=Gambia;GN=Guinea;GP=Guadeloupe;GQ=Equatorial Guinea;"
    "GR=Greece;GS=South Georgia and the South Sandwich Islands;GT=Guatemala;"
    "GU=Guam;GW=Guinea-Bissau;GY=Guyana";

const _kHK =
    "HK=Hong Kong;HM=Heard Island and McDonald Islands;HN=Honduras;HR=Croatia;"
    "HT=Haiti;HU=Hungary;ID=Indonesia;IE=Ireland;IL=Israel;IM=Isle of Man;"
    "IN=India;IO=British Indian Ocean Territory;IQ=Iraq;IR=Iran;IS=Iceland;"
    "IT=Italy;JE=Jersey;JM=Jamaica;JO=Jordan;JP=Japan;KE=Kenya;KG=Kyrgyzstan;"
    "KH=Cambodia;KI=Kiribati;KM=Comoros;KN=Saint Kitts and Nevis;"
    "KP=North Korea;KR=South Korea;KW=Kuwait;KY=Cayman Islands;KZ=Kazakhstan";

const _kLM =
    "LA=Laos;LB=Lebanon;LC=Saint Lucia;LI=Liechtenstein;LK=Sri Lanka;"
    "LR=Liberia;LS=Lesotho;LT=Lithuania;LU=Luxembourg;LV=Latvia;LY=Libya;"
    "MA=Morocco;MC=Monaco;MD=Moldova;ME=Montenegro;MF=Saint Martin;"
    "MG=Madagascar;MH=Marshall Islands;MK=North Macedonia;ML=Mali;MM=Myanmar;"
    "MN=Mongolia;MO=Macao;MP=Northern Mariana Islands;MQ=Martinique;"
    "MR=Mauritania;MS=Montserrat;MT=Malta;MU=Mauritius;MV=Maldives;MW=Malawi;"
    "MX=Mexico;MY=Malaysia;MZ=Mozambique";

const _kNP =
    "NA=Namibia;NC=New Caledonia;NE=Niger;NF=Norfolk Island;NG=Nigeria;"
    "NI=Nicaragua;NL=Netherlands;NO=Norway;NP=Nepal;NR=Nauru;NU=Niue;"
    "NZ=New Zealand;OM=Oman;PA=Panama;PE=Peru;PF=French Polynesia;"
    "PG=Papua New Guinea;PH=Philippines;PK=Pakistan;PL=Poland;"
    "PM=Saint Pierre and Miquelon;PN=Pitcairn;PR=Puerto Rico;PS=Palestine;"
    "PT=Portugal;PW=Palau;PY=Paraguay";

const _kQS =
    "QA=Qatar;RE=Réunion;RO=Romania;RS=Serbia;RU=Russia;RW=Rwanda;"
    "SA=Saudi Arabia;SB=Solomon Islands;SC=Seychelles;SD=Sudan;SE=Sweden;"
    "SG=Singapore;SH=Saint Helena;SI=Slovenia;SJ=Svalbard and Jan Mayen;"
    "SK=Slovakia;SL=Sierra Leone;SM=San Marino;SN=Senegal;SO=Somalia;"
    "SR=Suriname;SS=South Sudan;ST=Sao Tome and Principe;SV=El Salvador;"
    "SX=Sint Maarten;SY=Syria;SZ=Eswatini";

const _kTZ =
    "TC=Turks and Caicos Islands;TD=Chad;TF=French Southern Territories;"
    "TG=Togo;TH=Thailand;TJ=Tajikistan;TK=Tokelau;TL=Timor-Leste;"
    "TM=Turkmenistan;TN=Tunisia;TO=Tonga;TR=Türkiye;TT=Trinidad and Tobago;"
    "TV=Tuvalu;TW=Taiwan;TZ=Tanzania;UA=Ukraine;UG=Uganda;"
    "UM=United States Minor Outlying Islands;US=United States;UY=Uruguay;"
    "UZ=Uzbekistan;VA=Holy See;VC=Saint Vincent and the Grenadines;"
    "VE=Venezuela;VG=British Virgin Islands;VI=U.S. Virgin Islands;"
    "VN=Vietnam;VU=Vanuatu;WF=Wallis and Futuna;WS=Samoa;YE=Yemen;YT=Mayotte;"
    "ZA=South Africa;ZM=Zambia;ZW=Zimbabwe";

// 28 states and 8 union territories. Each is well inside the 80-character cap
// that save_user_preferences enforces on `state`.
const _kIndiaSubdivisions =
    "Andaman and Nicobar Islands;Andhra Pradesh;Arunachal Pradesh;Assam;Bihar;"
    "Chandigarh;Chhattisgarh;Dadra and Nagar Haveli and Daman and Diu;Delhi;"
    "Goa;Gujarat;Haryana;Himachal Pradesh;Jammu and Kashmir;Jharkhand;"
    "Karnataka;Kerala;Ladakh;Lakshadweep;Madhya Pradesh;Maharashtra;Manipur;"
    "Meghalaya;Mizoram;Nagaland;Odisha;Puducherry;Punjab;Rajasthan;Sikkim;"
    "Tamil Nadu;Telangana;Tripura;Uttar Pradesh;Uttarakhand;West Bengal";
