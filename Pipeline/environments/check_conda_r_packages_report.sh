#!/bin/bash

env_name="group10_R"

packages=(
  dplyr
  stringr
  tibble
  ggplot2
  gridExtra
  randomForest
  data.table
  purrr
  table1
  openxlsx
  scales
  corrplot
  missForestPredict
  dagitty
  glmnet
  igraph
  pheatmap
  sharp
  fake
  pROC
  ranger
  CMake
)

map_to_conda_name() {
  case "$1" in
    randomForest) echo "r-randomforest" ;;
    data.table) echo "r-data.table" ;;
    gridExtra) echo "r-gridextra" ;;
    pROC) echo "r-proc" ;;
    CMake) echo "cmake" ;;
    *) 
      lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
      echo "r-$lower"
      ;;
  esac
}

ok_list=()
missing_list=()

for pkg in "${packages[@]}"; do
  conda_pkg=$(map_to_conda_name "$pkg")
  if conda list -n "$env_name" | awk '{print $1}' | grep -Fxq "$conda_pkg"; then
    ok_list+=("$pkg -> $conda_pkg")
  else
    missing_list+=("$pkg -> $conda_pkg")
  fi
done

echo "===== Packages found in conda env export ====="
for x in "${ok_list[@]}"; do
  echo "$x"
done

echo
echo "===== Packages NOT found in conda env ====="
for x in "${missing_list[@]}"; do
  echo "$x"
done
