# Worker 任务：UC 网盘 iOS 原生实现（只做 UC，不做夸克）

## 目标
实现 UC 网盘的 FishDriveService（替换 PendingFishDriveService）。

## 已取证端点
- 基址 `https://pc-api.uc.cn/1/clouddrive/`；账号 `https://drive.uc.cn/account/info?fr=pc&platform=pc`
- 扫码 `https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t=`
- 文件 info `.../file/info?pr=UCBrowser&fr=pc&fid=`；列表参数 `pdir_fid=0&_page=1&_size=200&_sort=file_type:asc,updated_at:desc&__t=`
- 分享 token `.../share/sharepage/token?pr=UCBrowser&fr=pc&uc_param_str=&__dt=&__t=`；下载 `.../file/download?pr=UCBrowser&fr=pc&sys=win32&ve=1.8.6&ut=`
- 任务 `task?pr=UCBrowser&fr=pc&uc_param_str=&task_id=`；会员 `.../member?...`
- UA `uc-cloud-drive/1.8.7 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch`
- Android action：uc_status/uc_scan/uc_token_scan/uc_thread/uc_clean

## 产出
- OK4KiOS/Network/UCDriveService.swift（网络层）
- OK4KiOS/Network/UCDriveServiceAdapter.swift（实现 FishDriveService）
- OK4KiOS/Network/FishDriveService.swift 注册（FishDriveRegistry 加 uc case）
- Tests/UCDriveServiceTests.swift（mock HTTP 生命周期测试）

## 约束与验证
同 TASK-quark_uc.md 的硬约束：不硬编码 token、动态 JSON 无损、扫码流程（创建→轮询→持久化→refresh→logout）、
证据不足诚实 protocolPending、swiftc -parse 验证、提交 push worker-ds-uc_topup、PROGRESS.md 记录。
