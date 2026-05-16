#!/bin/bash

# 1. 隔离可能存在的全局 NumPy 冲突
export PYTHONNOUSERSITE=1

# 2. 定义目录变量
INPUT_DIR="all_merged_bins"
MAIN_OUT="checkm2_output_final"
TMP_DIR="tmp_checkm2_splits"

mkdir -p "$MAIN_OUT"
mkdir -p "$TMP_DIR"

echo "=== Step 1: 正在生成并统计 MAG 文件列表 ==="
# 获取所有 .fa 文件的绝对路径，存入临时文件
find "$(pwd)/$INPUT_DIR" -name "*.fa" > "$TMP_DIR/all_mags_list.txt"
total_files=$(wc -l < "$TMP_DIR/all_mags_list.txt")
echo "总共发现 $total_files 个 MAG 文件。"

echo "=== Step 2: 正在将列表平均切分为 5 份 ==="
# 按行数均分成 5 份
split -d -n l/5 "$TMP_DIR/all_mags_list.txt" "$TMP_DIR/sub_list_"

echo "=== Step 3: 正在构建 5 个并行的输入文件夹并启动 CheckM2 ==="
for i in {00..04}; do
    list_file="$TMP_DIR/sub_list_${i}"

    if [ -f "$list_file" ]; then
        batch_in="$TMP_DIR/batch_in_${i}"
        batch_out="$TMP_DIR/batch_out_${i}"
        mkdir -p "$batch_in"

        # 使用软链接，不占用额外磁盘空间
        while read -r file; do
            ln -s "$file" "$batch_in/"
        done < "$list_file"

        file_count=$(wc -l < "$list_file")
        echo " -> 启动批次 $i : 分配 $file_count 个 MAGs，使用 20 线程..."

        # 末尾的 & 让这 5 个 checkm2 核心命令同时在后台并发跑
        checkm2 predict \
            --threads 20 \
            --input "$batch_in" \
            --output-directory "$batch_out" \
            -x fa > "$TMP_DIR/batch_${i}.log" 2>&1 &
    fi
done

echo "=========================================================="
echo " 5 个 CheckM2 进程已成功启动！总计正在使用 100 个线程。"
echo "=========================================================="
echo "正在等待所有后台任务结束..."

# 等待上述 5 个后台并行的 checkm2 全部算完
wait

echo "=== Step 4: 所有批次运行结束，正在合并质量评估报告 ==="
if [ -f "$TMP_DIR/batch_out_00/quality_report.tsv" ]; then
    cp "$TMP_DIR/batch_out_00/quality_report.tsv" "$MAIN_OUT/quality_report_all.tsv"
fi

for i in {01..04}; do
    res_file="$TMP_DIR/batch_out_${i}/quality_report.tsv"
    if [ -f "$res_file" ]; then
        tail -n +2 "$res_file" >> "$MAIN_OUT/quality_report_all.tsv"
    fi
done

final_lines=$(wc -l < "$MAIN_OUT/quality_report_all.tsv")
echo "=== 完成！最终合并后的质量报告包含 $((final_lines - 1)) 个 MAG 的数据 ==="
echo "结果输出路径: $MAIN_OUT/quality_report_all.tsv"
