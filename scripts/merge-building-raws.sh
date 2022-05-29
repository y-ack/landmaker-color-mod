#!/bin/sh

# arguments: list of directories to run in
# requires imagemagick
for dir in "$@"
do
  convert -depth 8 -size 32x32 GRAY:$dir/_BL_NPRI*00-W-32-H-32.raw png8:$dir/house.png
  convert -depth 8 -size 48x48 GRAY:$dir/_BL_NPRI*70-W-48-H-48.raw png8:$dir/bronze.png
  convert -depth 8 -size 80x80 GRAY:$dir/_BL_NPRI*71-W-80-H-80.raw png8:$dir/silver.png
  convert -depth 8 -size 96x96 GRAY:$dir/_BL_NPRI*72-W-96-H-96.raw png8:$dir/gold.png
  convert -depth 8 -size 128x112 GRAY:$dir/_BL_NPRI*73-W-128-H-112.raw png8:$dir/platinum.png

  convert -background "#000" +append $dir/house.png $dir/bronze.png $dir/silver.png $dir/gold.png $dir/platinum.png $dir/buildings-merged.png
  convert -depth 8 $dir/buildings-merged.png GRAY:$dir/buildings-merged-W-384-H-112.raw

  # cleanup
  rm $dir/house.png $dir/bronze.png $dir/silver.png $dir/gold.png $dir/platinum.png $dir/buildings-merged.png
done

