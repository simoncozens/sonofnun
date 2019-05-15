#!/bin/sh

mkdir original-data
cd original-data
wget https://joshuaproject.net/assets/media/data/jpharvfielddataonly.zip
unzip jpharvfielddataonly.zip
for t in `mdb-tables JPHarvestField.accdb`
do
  echo "Extracting $t..."
  mdb-export JPHarvestField.accdb $t > $t.csv
done