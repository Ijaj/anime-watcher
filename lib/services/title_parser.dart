/// Parses release-style folder and file names, e.g.
/// `[Group] Attack.on.Titan.S01-S03.1080p.BluRay.x265` →
/// title "Attack On Titan", seasons [1, 2, 3].
class ParsedTitle {
  final String title;
  final List<int> seasons;
  final int? year;
  final bool hasParts;

  const ParsedTitle({required this.title, this.seasons = const [], this.year, this.hasParts = false});

  @override
  String toString() => 'ParsedTitle($title, seasons: $seasons, year: $year)';
}

class TitleExtractor {
  static final _bracketGroups = RegExp(r'\[[^\]]*\]|\{[^}]*\}|【[^】]*】');
  static final _parenGroups = RegExp(r'\(([^)]*)\)');
  static final _separators = RegExp(r'[.\s_]+');

  // S01, S1, S02P01, S01-S03, S01-03, S01E05
  static final _seasonToken = RegExp(r'^S(\d{1,2})(?:E\d{1,4})?(P\d{1,2})?(?:-S?(\d{1,2}))?$', caseSensitive: false);
  static final _seasonWord = RegExp(r'^season(\d{1,2})?$', caseSensitive: false);
  static final _number = RegExp(r'^\d{1,2}$');
  static final _year = RegExp(r'^(19|20)\d{2}$');

  static final _technical = RegExp(
    r'^(\d{3,4}p|4k|uhd|hdr|hdr10|dv|sdr|x26[45]|h26[45]|hevc|avc|av1|xvid|10bit|8bit|'
    r'web|web-?dl|web-?rip|webrip|hdtv|bluray|blu-ray|bdrip|brrip|bd|dvdrip|dvd|remux|'
    r'dual|dual-audio|multi|multi-sub|aac|aac2|ac3|eac3|ddp?(5\.1|2\.0)?|ddp5|dts|flac|opus|atmos|'
    r'complete|batch|uncensored|repack|proper|nf|amzn|cr|dsnp|hmax|subbed|dubbed|eng|jpn|jap)$',
    caseSensitive: false,
  );

  static const _specialsNames = {'specials', 'special', 'sp', 'ova', 'ovas', 'oad', 'extras'};

  static ParsedTitle extract(String name) {
    if (name.trim().isEmpty) return const ParsedTitle(title: '');

    var cleaned = name.replaceAll(_bracketGroups, ' ');
    int? year;
    cleaned = cleaned.replaceAllMapped(_parenGroups, (m) {
      final inner = m.group(1)!.trim();
      if (_year.hasMatch(inner)) year ??= int.parse(inner);
      return ' ';
    });

    final tokens = cleaned.split(_separators).where((t) => t.isNotEmpty && t != '-' && t != '+').toList();
    final titleTokens = <String>[];
    final seasons = <int>[];
    var titleDone = false;
    var hasParts = false;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      final s = _seasonToken.firstMatch(token);
      if (s != null) {
        final start = int.parse(s.group(1)!);
        final end = s.group(3) != null ? int.parse(s.group(3)!) : start;
        for (var n = start; n <= end; n++) {
          if (!seasons.contains(n)) seasons.add(n);
        }
        if (s.group(2) != null) hasParts = true;
        titleDone = true;
        continue;
      }

      final w = _seasonWord.firstMatch(token);
      if (w != null) {
        final inline = w.group(1);
        if (inline != null) {
          seasons.add(int.parse(inline));
          titleDone = true;
        } else if (i + 1 < tokens.length && _number.hasMatch(tokens[i + 1])) {
          seasons.add(int.parse(tokens[++i]));
          titleDone = true;
        } else if (!titleDone) {
          titleTokens.add(token);
        }
        continue;
      }

      if (_technical.hasMatch(token)) {
        titleDone = true;
        continue;
      }

      // A bare year right before the tech/season tokens (or at the end) is a
      // release year, not part of the title: "Blade.Runner.2049.1080p" is the
      // exception we accept getting wrong.
      if (!titleDone && titleTokens.isNotEmpty && _year.hasMatch(token)) {
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        if (next == null || _technical.hasMatch(next) || _seasonToken.hasMatch(next)) {
          year ??= int.parse(token);
          titleDone = true;
          continue;
        }
      }

      if (!titleDone) titleTokens.add(token);
    }

    return ParsedTitle(
      title: _capitalizeWords(titleTokens.join(' ')),
      seasons: seasons,
      year: year,
      hasParts: hasParts,
    );
  }

  /// Season number implied by a folder name, e.g. `Season 2`, `S02`,
  /// `Show.S02.1080p`, `Specials` (0). Null if the name has no season.
  static int? seasonFromFolderName(String name) {
    if (_specialsNames.contains(name.trim().toLowerCase())) return 0;
    final parsed = extract(name);
    return parsed.seasons.isEmpty ? null : parsed.seasons.first;
  }

  static String _capitalizeWords(String str) =>
      str.split(' ').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// Season/episode numbers parsed from a video file name.
class EpisodeNumber {
  final int? season;
  final int? episode;

  const EpisodeNumber({this.season, this.episode});
}

class EpisodeParser {
  static final _sxe = RegExp(r'S(\d{1,2})[ ._-]?E(\d{1,4})', caseSensitive: false);
  static final _nxn = RegExp(r'\b(\d{1,2})x(\d{2,3})\b');
  static final _ep = RegExp(r'(?:^|[^a-z])(?:E|EP|Episode)[ ._-]?(\d{1,4})(?:v\d)?(?![\d])', caseSensitive: false);
  static final _dash = RegExp(r'\s-\s(\d{1,4})(?:v\d)?(?!\d)');
  static final _bracketNumber = RegExp(r'\[(\d{1,4})(?:v\d)?\]');
  static final _groups = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
  static final _standalone = RegExp(r'(?:^|[\s._-])(\d{1,3})(?:v\d)?(?=$|[\s._-])');

  static EpisodeNumber parse(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;

    final sxe = _sxe.firstMatch(name) ?? _nxn.firstMatch(name);
    if (sxe != null) {
      return EpisodeNumber(season: int.parse(sxe.group(1)!), episode: int.parse(sxe.group(2)!));
    }

    final ep = _ep.firstMatch(name);
    if (ep != null) return EpisodeNumber(episode: int.parse(ep.group(1)!));

    final dash = _dash.firstMatch(name.replaceAll(_groups, ' '));
    if (dash != null) return EpisodeNumber(episode: int.parse(dash.group(1)!));

    final bracket = _bracketNumber.firstMatch(name);
    if (bracket != null) return EpisodeNumber(episode: int.parse(bracket.group(1)!));

    // Last resort: the last standalone 1–3 digit number outside of tags.
    final matches = _standalone.allMatches(name.replaceAll(_groups, ' ')).toList();
    if (matches.isNotEmpty) return EpisodeNumber(episode: int.parse(matches.last.group(1)!));

    return const EpisodeNumber();
  }
}
