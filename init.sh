#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

read -r -p "请输入顶层模块名: " top_name

if [[ -z "${top_name}" ]]; then
    echo "错误: 顶层模块名不能为空" >&2
    exit 1
fi

if [[ ! "${top_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "错误: 顶层模块名必须是合法的 SystemVerilog 标识符" >&2
    echo "示例: TEST_PLATFORM, my_top, Top1" >&2
    exit 1
fi

vsrc_dir="vsrc"
sv_file="${vsrc_dir}/${top_name}.sv"
makefile="makefile"
csrc_dir="csrc"

mkdir -p "${vsrc_dir}"

if [[ -e "${sv_file}" ]]; then
    echo "错误: ${sv_file} 已存在，为避免覆盖请换一个模块名" >&2
    exit 1
fi

cat > "${sv_file}" <<SVEOF
module ${top_name} (
    input logic clk,
    input logic rst_n
);

endmodule
SVEOF

if [[ ! -f "${makefile}" ]]; then
    echo "错误: 未找到 ${makefile}，请先创建 makefile" >&2
    exit 1
fi

tmp_makefile="$(mktemp)"
awk -v top_name="${top_name}" '
    BEGIN { updated = 0 }
    /^TOP_NAME[[:space:]]*([?+:]?=)/ {
        print "TOP_NAME ?= " top_name
        updated = 1
        next
    }
    { print }
    END {
        if (!updated) {
            print ""
            print "TOP_NAME ?= " top_name
        }
    }
' "${makefile}" > "${tmp_makefile}"
mv "${tmp_makefile}" "${makefile}"

if [[ -d "${csrc_dir}" ]]; then
    while IFS= read -r -d '' c_file; do
        sed -E -i \
            -e "s/#include \"V[A-Za-z_][A-Za-z0-9_]*__Syms\.h\"/#include \"__VERILATOR_TOP_SYMS_PLACEHOLDER__\"/g" \
            -e "s/#include \"V[A-Za-z_][A-Za-z0-9_]*__Dpi\.h\"/#include \"__VERILATOR_TOP_DPI_PLACEHOLDER__\"/g" \
            -e "s/#include \"V[A-Za-z_][A-Za-z0-9_]*\.h\"/#include \"V${top_name}.h\"/g" \
            -e "s/#include \"__VERILATOR_TOP_SYMS_PLACEHOLDER__\"/#include \"V${top_name}__Syms.h\"/g" \
            -e "s/#include \"__VERILATOR_TOP_DPI_PLACEHOLDER__\"/#include \"V${top_name}__Dpi.h\"/g" \
            -e "s/\bV[A-Za-z_][A-Za-z0-9_]*([[:space:]]*\*[[:space:]]*dut\b)/V${top_name}\1/g" \
            -e "s/(dut[[:space:]]*=[[:space:]]*new[[:space:]]+)V[A-Za-z_][A-Za-z0-9_]*/\1V${top_name}/g" \
            "${c_file}"
    done < <(find "${csrc_dir}" -type f \( \
        -name "*.h" -o -name "*.hh" -o -name "*.hpp" -o \
        -name "*.c" -o -name "*.cc" -o -name "*.cpp" \
    \) -print0)
fi

echo "已创建 ${sv_file}"
echo "已设置 TOP_NAME ?= ${top_name}"
echo "已同步 csrc 中的 Verilator 顶层头文件和类型为 V${top_name}"
