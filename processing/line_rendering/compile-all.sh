find ./*/* -name compile.sh -type f -execdir echo "$PWD" {} \; -execdir bash compile.sh {} \;
