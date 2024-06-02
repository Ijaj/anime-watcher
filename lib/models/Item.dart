
class Item{
  int id = -1;
  int libraryId;
  String name;
  String rootPath;
  Type type;
  List<String> genre;
  // int seasons = 0;
  int releasedSeasons = 0;
  bool onGoing = false;
  Map<int, String> seasons = <int, String>{};  // if season path string includes *, then this season has multiple parts
  String imageMid;
  String imageLg;
  List<String> extraImages = [];

  Item({
    required this.libraryId,
    required this.name,
    required this.rootPath,
    required this.genre,
    required this.imageMid,
    required this.imageLg,
    required this.type,
    this.id = -1,
    this.seasons = const {},
    this.extraImages = const [],
    this.onGoing = false,
    this.releasedSeasons = 0
  });

  static Item parse({
    required String selectedDir,
    required int? id,
    required dynamic r,
    required Type type,
    required seasons,
    extraImages = const [],
    onGoing = false,
    releasedSeasons = 0
}){
    // this is assuming data from MAL, later, add check for OMDB api
    return Item(
      libraryId: r['id'],
      rootPath: selectedDir,
      name: r['title'],
      genre: r['genres'].map((item) => item['name']).toList(),
      imageMid: r['main_picture']['medium'],
      imageLg: r['main_picture']['large'],
      type: type,
      seasons: seasons,
      extraImages: extraImages,
      onGoing: r['status'] == 'currently_airing',
      releasedSeasons: releasedSeasons
    );
  }
}

enum Type{
  anime,
  movie,
  series
}