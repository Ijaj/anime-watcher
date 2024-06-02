// first, get the folder name
// then, parse the title
// for now, assume that only series will be added to the list, worry about movies later
// tokenize the title
// first, check if SXX patters exists, if so, then it is a series, else it is a movie
// if SXX pattern also includes PX, then this means that this season has multiple parts, dont worry about merging now

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:io';


class ExtractionResult{
    String title = '';
    List<int> seasons = [];

    ExtractionResult({required this.title, required this.seasons});
  }

  class TitleExtractor {
    static const _commonTechnicalDetails = [
      '1080p', 'WEB-DL', 'BDRip', 'DUAL', 'x264', 'x265',
      'ANiMEZ', 'FLUX', 'TEPES', 'EMBER',
    ];

    static const _titleDictionary = [
      'season', 'S', 'series', 'episode', 'ep', 'part', 'pt',
    ];

    static ExtractionResult extractTitleAndSeasonFromFolderName(String folderName) {
      if(folderName.isEmpty) return ExtractionResult(title: '', seasons: []);

      final List<String> tokens = folderName.split(RegExp(r'[.\s-_]'));
      final List<String> titleTokens = <String>[];
      bool skipTokens = false;
      List<int> seasons = [];

      for (var i = 0; i < tokens.length; i++) {
        final token = tokens[i];
        if(token.isEmpty){
          continue;
        }

        // ignore any [] at first
        if(token[0] == '['){
          continue;
        }

        // first check for season, if no seasons, then it is movie
        if(seasons.length < 2){
          if((token[0] == 'S' || token[0] == 's')){
            // later, add detection for parts, like : S02P01, S02P02, merge them together
            if(token.contains('P') || token.contains('p')){
              if (kDebugMode) {
                print('has parts');
              }
            }
            int? number = int.tryParse(token.substring(1));
            if(number != null) {
              seasons.add(number);
              skipTokens = true;
            }
          }
        }

        // check if year, surrounded by ()
        if(token[0] == '(' && token[token.length - 1] == ')'){
          continue;
          //usually only the year has (), but even then, give a check
          String year = token.substring(1, token.length - 2);
          if(year.length == 4 && int.tryParse(year) != null){
            // it is year, but dont really need it rn.
          }
        }

        if (skipTokens ||
            _commonTechnicalDetails.contains(token.toLowerCase()) ||
            _titleDictionary.contains(token.toLowerCase())) {
          continue;
        }

        if (titleTokens.isNotEmpty && (_isSingleChar(token))) {
          // titleTokens.last += token.padLeft(1).padRight(1);
          titleTokens.add(token);
        } else {
          titleTokens.add(token);
        }
      }

      final title = titleTokens.join(' ');
      return ExtractionResult(
        title: _capitalizeAllWords(title),
        seasons: seasons,
      );
    }

    static bool _isSingleChar(String str) {
      return str.length == 1;
    }

    static String _capitalizeAllWords(String str) {
      final words = str.split(' ');
      return words.map((word) => '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
    }

    static Future<Map<int, String>> getSeasonsInsideFolder(String folderPath) async {
      List<FileSystemEntity> paths = await getDirectoryContents(folderPath);
      Map<int, String> seasons = {};

      ExtractionResult result;
      for (FileSystemEntity fs in paths) {
        // paths.add(fs.path);
        ExtractionResult result = extractTitleAndSeasonFromFolderName(fs.path);
        if(seasons.containsKey(result.seasons[0])){
          seasons[result.seasons[0]] = '${seasons[result.seasons[0]]!}|${fs.path}';
        }
        else{
          seasons[result.seasons[0]] = fs.path;
        }
      }
      return seasons;
    }

    static Future<List<FileSystemEntity>> getDirectoryContents(String directoryPath) async {
      final directory = Directory(directoryPath);
      try {
        final entities = await directory.list().toList();
        return entities;
      } catch (e) {
        print('Error getting directory contents: $e');
        return [];
      }
    }
  }

class Anime{
  static Future<List<dynamic>> searchAnime(String title) async {
    try {
      print('searching for: $title');
      final response = await Dio().get(
        'https://api.myanimelist.net/v2/anime',
        queryParameters: {
          'q': title,
          'limit': 10,
        },
        options: Options(
          headers: {
            'X-MAL-Client-ID': '0e349e6cf6aa67da3ad146ec4d58d91d',
          },
        ),
      );
      print(response.data['data']);
      print(response.data['data'].runtimeType);
      return response.data['data'];
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getAnimeDetails(int animeId) async {
    try {
      final response = await Dio().get(
        'https://api.myanimelist.net/v2/anime/$animeId',
        queryParameters: {
          'fields': [
            'id',
            'title',
            'main_picture',
            'alternative_titles',
            'start_date',
            'end_date',
            'synopsis',
            'mean',
            'rank',
            'popularity',
            'nsfw',
            'media_type',
            'status',
            'genres',
            'num_episodes',
            'start_season',
            'broadcast',
            'source',
            'average_episode_duration',
            'rating',
            'pictures',
            'background',
            'studios',
            'statistics'
          ]
        },
        options: Options(
          headers: {
            'X-MAL-Client-ID': '0e349e6cf6aa67da3ad146ec4d58d91d',
          },
        ),
      );

      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getSeriesDetails(int seriesId) async {
    try {
      final response = await Dio().get(
        'https://api.myanimelist.net/v2/anime/$seriesId',
        options: Options(
          headers: {
            'X-MAL-Client-ID': '0e349e6cf6aa67da3ad146ec4d58d91d',
          },
        ),
      );

      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSeasonEpisodes(int seriesId) async {
    try {
      final response = await Dio().get(
        'https://api.myanimelist.net/v2/anime/$seriesId/episodes',
        queryParameters: {
          'fields': 'episode_number,title,aired',
        },
        options: Options(
          headers: {
            'X-MAL-Client-ID': '0e349e6cf6aa67da3ad146ec4d58d91d',
          },
        ),
      );

      return List<Map<String, dynamic>>.from(response.data['episodes']);
    } catch (e) {
      rethrow;
    }
  }
}