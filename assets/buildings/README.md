# 建物データ（PLATEAU GeoJSON）置き場

ここに PLATEAU から変換した建物 GeoJSON を置くと、正確な高さ付きの
実建物で影を計算できます（現状の既定は OSM/Overpass）。

## 取り込み手順
1. **データ取得**: [G空間情報センター](https://www.geospatial.jp/ckan/dataset/plateau) で
   「仙台市」の建築物モデル（`bldg`, CityGML）をダウンロード。
2. **GeoJSON 変換**（どれか1つ）:
   - GUI: [PLATEAU GIS Converter](https://github.com/Project-PLATEAU/PLATEAU-GIS-Converter)
     （出力形式 GeoJSON。`bldg:measuredHeight` を高さ属性として残す）
   - CLI: PlateauKit `plateaukit export-geojson ...`
3. 変換した GeoJSON を **`assets/buildings/sendai.geojson`** としてここに置く。
4. `lib/features/map/map_screen.dart` の `_buildingRepo` を
   `AssetBuildingRepository('assets/buildings/sendai.geojson')` に変更。
5. `flutter pub get` → 再実行。

> GeoJSON 仕様: FeatureCollection / Polygon、座標は `[経度, 緯度]`、
> 各 Feature の properties に高さ（`measuredHeight` / `height` 等）を含めること。
> パーサ実装: `lib/core/geo/geojson_parser.dart`
