# GNU patch 2.7.1 移植专项(armv7 iOS 10.3.3)

> 包:`patch4_2.7.1-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 上游:ftp.gnu.org/gnu/patch/patch-2.7.1(GPL-3+,自带 gnulib)

## 1. 验收

- `patch --version` → GNU patch 2.7.1 ✓
- 功能闭环:宿主做 unified diff → 设备 `patch a.txt < test.diff` →
  md5 与预期一致(`98fb0520a4fc`)✓
- check-undefined:116/116 全解析 ✓

## 2. 墙实录(gnulib 恒真探针全家桶)

1. **恒真探针五件套**(dynamic_lookup 下"编译+链接"探针恒真):
   `HAVE_FUTIMENS/HAVE_FUTIMESAT/HAVE_UTIMENSAT/HAVE_NANOTIME/
   HAVE_CANONICALIZE_FILE_NAME` 全是假阳性(iOS 10 无这些 API)。
2. **§10 的 gnulib 变体**:config.hin 的 `#undef X` 是**占位符**,
   config.status 会按(假)探针结果写回 `#define X 1`——只改 config.h
   会被模板再生吃回。正解三件套:**删模板占位行 + 改 config.h +
   touch config.h 压 mtime**,缺一不可(教训:改模板后 mtime 变新,
   下次 make 触发再生,把没删干净的占位又写回来)。
3. **msvc-inval/msvc-nothrow**:Windows 专属 gnulib 模块,恒真探针
   (`_set_invalid_parameter_handler`)误纳,POSIX 下编译不过 → 从
   lib/Makefile 的 gl_LIBOBJS/gl_LTLIBOBJS 剔除;连带
   `MSVC_INVALID_PARAMETER_HANDLING` define 删除。
4. **xalloc_die 重复定义**:patch 自带实现(src/util.c),gnulib 的
   xalloc-die.o 重复 → 手链时排除。
5. **src-compat.c 兜底**:gnulib 生成的 unistd.h 在 REPLACE_WRITE(假)
   下重定向 write→rpl_write,但 lib/write.c 在 POSIX 编译为空 →
   12 行 compat 对象直通真 write(2);同文件定义
   `gl_msvc_inval_ensure_handler` 空实现。
6. **链接 = 手链**(§2 归档规则):src/*.o + src-compat.o + lib/*.o
   (排除 xalloc-die),libtool 归档不参与。

## 3. 相关文件

| 文件 | 作用 |
|---|---|
| `patch/src/` | 源树(压制产物保留,build.sh 幂等) |
| `patch/src-compat.c` | gnulib 尾巴 shim |
| `patch/include/crt_externs.h` | gnulib Darwin 分支需要(SDK 缺,Libc 取) |
| `patch/build.sh` / `make-deb.sh` | 构建(压制+手链固化)/ 打包 |
