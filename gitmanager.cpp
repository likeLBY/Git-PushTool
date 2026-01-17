#include "gitmanager.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QRegularExpression>
#include <QDirIterator>
#include <QCryptographicHash>
#include <QCoreApplication>
#include <QSettings>
#include <QDebug>
#include <QtConcurrent>
#include <QFutureWatcher>
#include <QDesktopServices>
#include <QUrl>

GitManager::GitManager(QObject *parent)
    : QObject(parent)
{
    // Create file system watcher
    m_watcher = new QFileSystemWatcher(this);
    
    // Create debounce timer (avoid too frequent refreshes)
    m_refreshTimer = new QTimer(this);
    m_refreshTimer->setSingleShot(true);
    m_refreshTimer->setInterval(800); // 减少到800ms，提高响应速度
    
    connect(m_refreshTimer, &QTimer::timeout, this, [this]() {
        if (m_pendingRefresh && !m_isLoading && !m_settingUpWatcher) {
            m_pendingRefresh = false;
            // 文件监控触发的刷新不显示加载状态，静默在后台运行
            parseStatusAsync(false);
        }
    });
    
    // Connect watcher signals
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        Q_UNUSED(path)
        m_pendingRefresh = true;
        m_refreshTimer->start();
    });
    
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &path) {
        qDebug() << "Directory changed:" << path;
        
        // 如果正在设置监控或批量操作模式，忽略变化
        if (m_settingUpWatcher || m_bulkOperationMode) {
            return;
        }
        
        // 防抖：只有当定时器不活跃时才触发刷新
        if (!m_refreshTimer->isActive()) {
            m_pendingRefresh = true;
            m_refreshTimer->start();
        }
        
        // 如果是根目录变化，可能有新的子文件夹创建，需要重新设置监控
        if (path == m_repoPath && !m_settingUpWatcher) {
            QTimer::singleShot(1500, this, [this]() {
                if (!m_repoPath.isEmpty() && !m_bulkOperationMode && !m_settingUpWatcher) {
                    setupFileWatcher(); // 重新设置监控以包含新文件夹
                }
            });
        }
        // 如果是子目录变化，也可能需要重新设置监控（新建子文件夹的情况）
        else if (path.startsWith(m_repoPath + "/") && !m_settingUpWatcher) {
            // 检查是否有新的子文件夹需要监控
            QTimer::singleShot(1000, this, [this, path]() {
                if (!m_repoPath.isEmpty() && !m_bulkOperationMode && !m_settingUpWatcher) {
                    // 检查这个路径下是否有新的子文件夹
                    QDir dir(path);
                    if (dir.exists()) {
                        QFileInfoList newDirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
                        bool hasNewDirs = false;
                        
                        // 检查是否有未监控的子文件夹
                        QStringList watchedPaths = m_watcher->directories();
                        for (const QFileInfo &info : newDirs) {
                            if (!watchedPaths.contains(info.absoluteFilePath())) {
                                hasNewDirs = true;
                                break;
                            }
                        }
                        
                        if (hasNewDirs) {
                            setupFileWatcher(); // 重新设置监控
                        }
                    }
                }
            });
        }
    });
    
    // Create async process for long operations
    m_asyncProcess = new QProcess(this);
    connect(m_asyncProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus exitStatus) {
        Q_UNUSED(exitStatus)
        QString errorOutput = QString::fromUtf8(m_asyncProcess->readAllStandardError()).trimmed();
        QString output = QString::fromUtf8(m_asyncProcess->readAllStandardOutput()).trimmed();
        
        setLoading(false);
        
        // Disable bulk operation mode after any async operation
        if (m_bulkOperationMode) {
            setBulkOperationMode(false);
        }
        
        if (exitCode != 0) {
            setError(m_asyncErrorPrefix + ": " + (errorOutput.isEmpty() ? output : errorOutput));
        } else {
            // Special handling for clone - set repo path after success
            if (m_asyncSuccessMsg == "克隆成功" && !m_cloneTargetPath.isEmpty()) {
                setRepoPath(m_cloneTargetPath);
                m_cloneTargetPath.clear();
            }
            emit operationSuccess(m_asyncSuccessMsg);
            
            // Auto refresh remote files if it was a file operation
            if (m_asyncSuccessMsg.contains("已保存并推送") || 
                m_asyncSuccessMsg.contains("已删除") ||
                m_asyncSuccessMsg.contains("已重命名")) {
                emit remoteFilesNeedRefresh();
            }
        }
        refresh();
    });
    
    // Load global git config on startup
    loadGlobalUserInfo();
}

QString GitManager::repoPath() const
{
    return m_repoPath;
}

void GitManager::setRepoPath(const QString &path)
{
    QString cleanPath = path;
    
    // Handle file:/// URLs from folder dialog or drag-drop
    if (cleanPath.startsWith("file:///")) {
        cleanPath = cleanPath.mid(8);
    }
    
    // URL decode (handle %20 for spaces, Chinese characters, etc.)
    cleanPath = QUrl::fromPercentEncoding(cleanPath.toUtf8());
    
    // Normalize path separators on Windows
    cleanPath = QDir::toNativeSeparators(cleanPath);
    
    // Remove trailing slashes
    while (cleanPath.endsWith('/') || cleanPath.endsWith('\\')) {
        cleanPath.chop(1);
    }
    
    if (m_repoPath != cleanPath) {
        m_repoPath = cleanPath;
        emit repoPathChanged();
        
        // Setup file watcher for the new repo
        setupFileWatcher();
        
        // Refresh first to check if it's a valid repo
        refresh();
        
        // Only add to recent repos if it's a valid git repository
        if (!cleanPath.isEmpty() && m_isValidRepo) {
            addRecentRepo(cleanPath);
        } else if (cleanPath.isEmpty()) {
            // When returning to home, emit signal to refresh recent repos list
            emit recentReposChanged();
        }
    }
}

void GitManager::setupFileWatcher()
{
    if (!m_watcher || m_settingUpWatcher) return;
    
    m_settingUpWatcher = true; // 防止重复调用
    
    // Remove all existing watched paths
    QStringList oldPaths = m_watcher->files() + m_watcher->directories();
    if (!oldPaths.isEmpty()) {
        m_watcher->removePaths(oldPaths);
    }
    
    if (m_repoPath.isEmpty()) {
        m_settingUpWatcher = false;
        return;
    }
    
    // 监控仓库根目录
    m_watcher->addPath(m_repoPath);
    
    // 监控 .git/index 文件
    QString gitIndex = m_repoPath + "/.git/index";
    if (QFileInfo(gitIndex).exists()) {
        m_watcher->addPath(gitIndex);
    }
    
    // 递归监控子文件夹（限制深度以避免性能问题）
    watchDirectoryRecursively(m_repoPath, 0);
    
    m_settingUpWatcher = false; // 重置标志
}

void GitManager::watchDirectoryRecursively(const QString &path, int depth)
{
    // 限制递归深度，避免性能问题
    if (depth > 3) return;
    
    QDir dir(path);
    if (!dir.exists()) return;
    
    // 跳过常见的不需要监控的文件夹
    static const QStringList skipFolders = {
        ".git", "node_modules", "build", "dist", "out", "target",
        ".idea", ".vscode", "__pycache__", ".cache", "vendor",
        "bin", "obj", "packages", ".gradle", ".next", ".nuxt"
    };
    
    QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    
    // 限制每层监控的文件夹数量
    int watchedCount = 0;
    const int maxWatchPerLevel = 25;
    
    for (const QFileInfo &info : entries) {
        if (watchedCount >= maxWatchPerLevel) break;
        
        QString folderName = info.fileName();
        if (skipFolders.contains(folderName, Qt::CaseInsensitive)) continue;
        
        QString folderPath = info.absoluteFilePath();
        
        // 监控这个文件夹
        m_watcher->addPath(folderPath);
        watchedCount++;
        
        // 递归监控子文件夹
        watchDirectoryRecursively(folderPath, depth + 1);
    }
}

void GitManager::setupFileWatcherAsync()
{
    if (!m_watcher || m_settingUpWatcher) return;
    
    m_settingUpWatcher = true;  // 设置标志防止重复调用
    
    QString repoPath = m_repoPath;
    
    QFuture<QStringList> future = QtConcurrent::run([repoPath]() -> QStringList {
        QStringList pathsToWatch;
        
        if (repoPath.isEmpty()) return pathsToWatch;
        
        // Add repo root directory
        pathsToWatch.append(repoPath);
        
        // Add files in root directory
        QDir rootDir(repoPath);
        QFileInfoList rootFiles = rootDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
        for (const QFileInfo &info : rootFiles) {
            if (info.size() < 1024 * 1024) { // < 1MB
                pathsToWatch.append(info.absoluteFilePath());
            }
        }
        
        // Add subdirectories (simplified version)
        std::function<void(const QString&, int)> watchDir = [&](const QString &path, int depth) {
            if (depth > 3) return; // Reduced depth for better performance
            
            QDir dir(path);
            if (!dir.exists()) return;
            
            static const QStringList skipFolders = {
                ".git", "node_modules", "build", "dist", "out", "target",
                ".idea", ".vscode", "__pycache__", ".cache", "vendor",
                "bin", "obj", "packages", ".gradle", ".next", ".nuxt"
            };
            
            pathsToWatch.append(path);
            
            QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
            int watchedCount = 0;
            const int maxWatchPerLevel = 20; // Reduced limit
            
            for (const QFileInfo &info : entries) {
                if (watchedCount >= maxWatchPerLevel) break;
                
                QString folderName = info.fileName();
                if (skipFolders.contains(folderName, Qt::CaseInsensitive)) continue;
                
                watchedCount++;
                watchDir(info.absoluteFilePath(), depth + 1);
            }
        };
        
        watchDir(repoPath, 0);
        return pathsToWatch;
    });
    
    QFutureWatcher<QStringList> *watcher = new QFutureWatcher<QStringList>(this);
    connect(watcher, &QFutureWatcher<QStringList>::finished, this, [this, watcher]() {
        QStringList pathsToWatch = watcher->result();
        
        // Remove all existing watched paths
        QStringList oldPaths = m_watcher->files() + m_watcher->directories();
        if (!oldPaths.isEmpty()) {
            m_watcher->removePaths(oldPaths);
        }
        
        // Add new paths in batches to avoid overwhelming the system
        const int batchSize = 50;
        for (int i = 0; i < pathsToWatch.size(); i += batchSize) {
            QStringList batch = pathsToWatch.mid(i, batchSize);
            m_watcher->addPaths(batch);
        }
        
        m_settingUpWatcher = false;  // 重置标志
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::watchDirectory(const QString &path, int depth)
{
    // Limit depth to 5 levels for better coverage
    if (depth > 5) return;
    
    QDir dir(path);
    if (!dir.exists()) return;
    
    // Skip common large/generated folders
    static const QStringList skipFolders = {
        ".git", "node_modules", "build", "dist", "out", "target",
        ".idea", ".vscode", "__pycache__", ".cache", "vendor",
        "bin", "obj", "packages", ".gradle", ".next", ".nuxt"
    };
    
    // Watch this directory itself
    m_watcher->addPath(path);
    
    // Watch files in this directory
    QFileInfoList files = dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
    int fileCount = 0;
    for (const QFileInfo &info : files) {
        if (fileCount >= 50) break; // Limit files per directory
        if (info.size() < 1024 * 1024) { // < 1MB
            m_watcher->addPath(info.absoluteFilePath());
            fileCount++;
        }
    }
    
    // Watch subdirectories
    QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    
    // Limit number of watched directories
    int watchedCount = 0;
    const int maxWatchPerLevel = 30;
    
    for (const QFileInfo &info : entries) {
        if (watchedCount >= maxWatchPerLevel) break;
        
        QString folderName = info.fileName();
        
        // Skip large/generated folders
        if (skipFolders.contains(folderName, Qt::CaseInsensitive)) continue;
        
        QString filePath = info.absoluteFilePath();
        watchedCount++;
        
        // Recursively watch subdirectories
        watchDirectory(filePath, depth + 1);
    }
}

QString GitManager::decodeOctalEscapes(const QString &input)
{
    QString str = input;
    
    // Handle quoted paths with octal escapes for non-ASCII characters
    if (str.startsWith('"') && str.endsWith('"')) {
        str = str.mid(1, str.length() - 2);
    }
    
    // Check if there are any octal escapes (backslash followed by digits)
    QRegularExpression octalPattern("\\\\[0-7]{3}");
    if (!octalPattern.match(str).hasMatch()) {
        // No octal escapes, just handle simple escapes and return
        str.replace("\\n", "\n");
        str.replace("\\t", "\t");
        str.replace("\\r", "\r");
        str.replace("\\\"", "\"");
        str.replace("\\\\", "\\");
        return str;
    }
    
    // Has octal escapes - need to decode byte by byte
    QByteArray bytes;
    for (int i = 0; i < str.length(); i++) {
        if (str[i] == '\\' && i + 1 < str.length()) {
            QChar next = str[i + 1];
            
            // Check for octal escape sequence (\xxx where x is 0-7)
            if (next >= '0' && next <= '7' && i + 3 < str.length()) {
                QString octalStr = str.mid(i + 1, 3);
                bool validOctal = (octalStr.length() == 3);
                for (int j = 0; j < octalStr.length() && validOctal; j++) {
                    if (octalStr[j] < '0' || octalStr[j] > '7') validOctal = false;
                }
                if (validOctal) {
                    bool ok;
                    int value = octalStr.toInt(&ok, 8);
                    if (ok) {
                        bytes.append(static_cast<char>(value));
                        i += 3;
                        continue;
                    }
                }
            }
            
            // Handle standard escape sequences
            if (next == 'n') { bytes.append('\n'); i++; continue; }
            if (next == 't') { bytes.append('\t'); i++; continue; }
            if (next == 'r') { bytes.append('\r'); i++; continue; }
            if (next == '"') { bytes.append('"'); i++; continue; }
            if (next == '\\') { bytes.append('\\'); i++; continue; }
            
            // Unknown escape, keep the backslash and next char
            bytes.append('\\');
            bytes.append(next.toLatin1());
            i++;
            continue;
        }
        
        // For ASCII characters, append directly
        if (str[i].unicode() < 128) {
            bytes.append(static_cast<char>(str[i].unicode()));
        } else {
            // Non-ASCII character that's not escaped - append its UTF-8 encoding
            QByteArray utf8Char = QString(str[i]).toUtf8();
            bytes.append(utf8Char);
        }
    }
    
    return QString::fromUtf8(bytes);
}

QString GitManager::currentBranch() const
{
    return m_currentBranch;
}

QStringList GitManager::branches() const
{
    return m_branches;
}

QStringList GitManager::localBranches() const
{
    return m_localBranches;
}

QStringList GitManager::remoteBranches() const
{
    return m_remoteBranches;
}

QVariantList GitManager::changedFiles() const
{
    return m_changedFiles;
}

QVariantList GitManager::stagedFiles() const
{
    return m_stagedFiles;
}

bool GitManager::isLoading() const
{
    return m_isLoading;
}

QString GitManager::lastError() const
{
    return m_lastError;
}

bool GitManager::isValidRepo() const
{
    return m_isValidRepo;
}

void GitManager::setLoading(bool loading)
{
    if (m_isLoading != loading) {
        m_isLoading = loading;
        emit isLoadingChanged();
    }
}

QString GitManager::translateGitError(const QString &error)
{
    QString translated = error;
    
    // Unfinished merge errors
    if (error.contains("unmerged files") || error.contains("MERGE_HEAD exists")) {
        translated = QString::fromUtf8("有未完成的合并：请先提交合并结果，或点击工具栏的「取消合并」按钮");
    }
    else if (error.contains("unfinished merge") || error.contains("conclude your merge")) {
        translated = QString::fromUtf8("有未完成的合并：请先提交或取消当前合并");
    }
    
    // Common push errors
    else if (error.contains("failed to push some refs")) {
        translated = QString::fromUtf8("推送失败：远程仓库有更新，请先拉取再推送");
    }
    else if (error.contains("Updates were rejected because the tip of your current branch is behind")) {
        translated = QString::fromUtf8("推送被拒绝：本地分支落后于远程分支，请先拉取更新");
    }
    else if (error.contains("Updates were rejected because the remote contains work")) {
        translated = "推送被拒绝：远程仓库包含本地没有的提交，请先拉取";
    }
    else if (error.contains("non-fast-forward")) {
        translated = "非快进推送被拒绝：请先拉取远程更新，或使用强制推送";
    }
    
    // Pull/fetch errors
    else if (error.contains("Could not resolve host")) {
        translated = "网络错误：无法解析主机名，请检查网络连接";
    }
    else if (error.contains("Connection refused") || error.contains("Connection timed out")) {
        translated = "连接失败：服务器拒绝连接或连接超时";
    }
    else if (error.contains("fatal: unable to access")) {
        translated = "无法访问远程仓库：请检查网络或仓库地址";
    }
    else if (error.contains("Permission denied") || error.contains("Authentication failed")) {
        translated = "认证失败：请检查用户名和密码/令牌是否正确";
    }
    
    // Merge conflicts
    else if (error.contains("CONFLICT") || error.contains("Automatic merge failed")) {
        translated = "合并冲突：请手动解决冲突后再提交";
    }
    else if (error.contains("Please commit your changes or stash them")) {
        translated = "有未提交的更改：请先提交或暂存当前更改";
    }
    else if (error.contains("Your local changes would be overwritten")) {
        translated = "本地更改会被覆盖：请先提交或暂存当前更改";
    }
    
    // File size errors (Gitee specific)
    else if (error.contains("File size limit") || error.contains("this exceeds") || error.contains("large file")) {
        translated = "文件过大：超过平台限制（Gitee限制100MB），请清理大文件";
    }
    else if (error.contains("RPC failed") || error.contains("curl")) {
        translated = "传输失败：文件可能过大或网络不稳定，请重试";
    }
    
    // Branch errors
    else if (error.contains("branch") && error.contains("already exists")) {
        translated = "分支已存在：该分支名称已被使用";
    }
    else if (error.contains("not a valid branch name")) {
        translated = "无效的分支名：分支名称格式不正确";
    }
    else if (error.contains("Cannot delete branch") && error.contains("checked out")) {
        translated = "无法删除分支：不能删除当前所在的分支";
    }
    
    // Repository errors
    else if (error.contains("not a git repository")) {
        translated = "不是Git仓库：当前目录未初始化为Git仓库";
    }
    else if (error.contains("repository not found") || error.contains("does not exist")) {
        translated = "仓库不存在：请检查仓库地址是否正确";
    }
    
    // Clone errors
    else if (error.contains("destination path") && error.contains("already exists")) {
        translated = "目标路径已存在：请选择其他位置或删除现有文件夹";
    }
    
    // Generic errors - keep original but add Chinese prefix
    else if (error.contains("fatal:") || error.contains("error:")) {
        translated = "Git错误：" + error;
    }
    
    return translated;
}

void GitManager::setError(const QString &error)
{
    QString translatedError = translateGitError(error);
    m_lastError = translatedError;
    emit lastErrorChanged();
    if (!translatedError.isEmpty()) {
        emit operationFailed(translatedError);
    }
}

QString GitManager::runGitCommand(const QStringList &args)
{
    if (m_repoPath.isEmpty()) {
        return QString();
    }

    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", args);
    process.waitForFinished(30000);

    if (process.exitCode() != 0) {
        QByteArray errorBytes = process.readAllStandardError();
        // Try UTF-8 first, then local encoding
        QString errorOutput = QString::fromUtf8(errorBytes);
        if (errorOutput.contains(QChar::ReplacementCharacter)) {
            errorOutput = QString::fromLocal8Bit(errorBytes);
        }
        errorOutput = errorOutput.trimmed();
        if (!errorOutput.isEmpty()) {
            qDebug() << "Git error:" << errorOutput;
        }
        return QString();
    }

    QByteArray rawOutput = process.readAllStandardOutput();
    
    // Try UTF-8 first
    QString output = QString::fromUtf8(rawOutput);
    
    // If UTF-8 produces replacement characters, try local encoding (GBK on Chinese Windows)
    if (output.contains(QChar::ReplacementCharacter)) {
        output = QString::fromLocal8Bit(rawOutput);
    }
    
    // Only remove trailing whitespace, not leading
    while (output.endsWith('\n') || output.endsWith('\r') || output.endsWith(' ')) {
        output.chop(1);
    }
    return output;
}

void GitManager::refresh()
{
    if (m_repoPath.isEmpty()) {
        m_isValidRepo = false;
        emit isValidRepoChanged();
        return;
    }

    setLoading(true);
    setError("");

    // Run all git commands asynchronously
    QString repoPath = m_repoPath;
    
    QFuture<void> future = QtConcurrent::run([this, repoPath]() {
        // Check if it's a valid git repo
        QProcess process;
        process.setWorkingDirectory(repoPath);
        process.start("git", {"rev-parse", "--git-dir"});
        process.waitForFinished(10000);
        bool isValidRepo = (process.exitCode() == 0);
        
        QString currentBranch;
        QString userName;
        QString userEmail;
        QStringList localBranches;
        QStringList remoteBranches;
        
        if (isValidRepo) {
            // Get current branch
            process.start("git", {"branch", "--show-current"});
            process.waitForFinished(10000);
            if (process.exitCode() == 0) {
                currentBranch = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
            }
            
            if (currentBranch.isEmpty()) {
                process.start("git", {"rev-parse", "--short", "HEAD"});
                process.waitForFinished(10000);
                if (process.exitCode() == 0) {
                    currentBranch = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
                }
            }
            
            // Get user info
            process.start("git", {"config", "user.name"});
            process.waitForFinished(5000);
            if (process.exitCode() == 0) {
                userName = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
            }
            
            process.start("git", {"config", "user.email"});
            process.waitForFinished(5000);
            if (process.exitCode() == 0) {
                userEmail = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
            }
            
            // Get local branches
            process.start("git", {"branch"});
            process.waitForFinished(10000);
            if (process.exitCode() == 0) {
                QString localOutput = QString::fromUtf8(process.readAllStandardOutput());
                QStringList localLines = localOutput.split('\n', Qt::SkipEmptyParts);
                for (const QString &line : localLines) {
                    QString branch = line.trimmed();
                    if (branch.startsWith("* ")) {
                        branch = branch.mid(2);
                    }
                    if (!branch.isEmpty()) {
                        localBranches.append(branch);
                    }
                }
            }
            
            // Get remote branches
            process.start("git", {"branch", "-r"});
            process.waitForFinished(10000);
            if (process.exitCode() == 0) {
                QString remoteOutput = QString::fromUtf8(process.readAllStandardOutput());
                QStringList remoteLines = remoteOutput.split('\n', Qt::SkipEmptyParts);
                for (const QString &line : remoteLines) {
                    QString branch = line.trimmed();
                    if (!branch.contains("->") && !branch.isEmpty()) {
                        // Remove origin/ prefix for display
                        if (branch.startsWith("origin/")) {
                            branch = branch.mid(7);
                        }
                        if (!remoteBranches.contains(branch) && !localBranches.contains(branch)) {
                            remoteBranches.append(branch);
                        }
                    }
                }
            }
        }
        
        // Update UI in main thread
        QMetaObject::invokeMethod(this, [this, isValidRepo, currentBranch, userName, userEmail, localBranches, remoteBranches]() {
            m_isValidRepo = isValidRepo;
            emit isValidRepoChanged();
            
            if (!isValidRepo) {
                setError("不是有效的 Git 仓库");
                setLoading(false);
                return;
            }
            
            // Update current branch
            if (m_currentBranch != currentBranch) {
                m_currentBranch = currentBranch;
                emit currentBranchChanged();
            }
            
            // Update user info
            if (m_userName != userName || m_userEmail != userEmail) {
                m_userName = userName;
                m_userEmail = userEmail;
                emit userInfoChanged();
            }
            
            // Update branches
            m_localBranches = localBranches;
            m_remoteBranches = remoteBranches;
            m_branches = localBranches + remoteBranches;
            emit branchesChanged();
            
            // Parse status asynchronously
            parseStatusAsync();
            
            // Update last commit time
            emit lastCommitTimeChanged();
            
        }, Qt::QueuedConnection);
    });
}

void GitManager::updateBranches()
{
    // Get local branches
    QString localOutput = runGitCommand({"branch"});
    m_localBranches.clear();
    
    QStringList localLines = localOutput.split('\n', Qt::SkipEmptyParts);
    for (const QString &line : localLines) {
        QString branch = line.trimmed();
        if (branch.startsWith("* ")) {
            branch = branch.mid(2);
        }
        if (!branch.isEmpty()) {
            m_localBranches.append(branch);
        }
    }
    
    // Get remote branches
    QString remoteOutput = runGitCommand({"branch", "-r"});
    m_remoteBranches.clear();
    
    QStringList remoteLines = remoteOutput.split('\n', Qt::SkipEmptyParts);
    for (const QString &line : remoteLines) {
        QString branch = line.trimmed();
        if (!branch.contains("->") && !branch.isEmpty()) {
            // Remove origin/ prefix for display
            if (branch.startsWith("origin/")) {
                branch = branch.mid(7);
            }
            if (!m_remoteBranches.contains(branch) && !m_localBranches.contains(branch)) {
                m_remoteBranches.append(branch);
            }
        }
    }
    
    // Combined list (local first, then remote-only)
    m_branches = m_localBranches + m_remoteBranches;
    
    emit branchesChanged();
}

void GitManager::parseStatus()
{
    // Set core.quotepath to false to show Chinese paths without escaping
    QProcess configProcess;
    configProcess.setWorkingDirectory(m_repoPath);
    configProcess.start("git", {"config", "core.quotepath", "false"});
    configProcess.waitForFinished(5000);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"status", "--porcelain=v1", "-uall"});
    process.waitForFinished(30000);
    
    QByteArray rawOutput = process.readAllStandardOutput();
    
    m_changedFiles.clear();
    m_stagedFiles.clear();

    // If git status returns empty, try to find untracked files manually
    if (rawOutput.isEmpty() || rawOutput.trimmed().isEmpty()) {
        // Use git ls-files to find untracked files
        process.start("git", {"ls-files", "--others", "--exclude-standard"});
        process.waitForFinished(30000);
        QByteArray untrackedOutput = process.readAllStandardOutput();
        
        if (!untrackedOutput.isEmpty()) {
            // Try UTF-8 first, then local encoding
            QString untrackedStr = QString::fromUtf8(untrackedOutput);
            if (untrackedStr.contains(QChar::ReplacementCharacter)) {
                untrackedStr = QString::fromLocal8Bit(untrackedOutput);
            }
            QStringList untrackedFiles = untrackedStr.split('\n', Qt::SkipEmptyParts);
            
            for (const QString &filePath : untrackedFiles) {
                if (filePath.isEmpty()) continue;
                
                QString fileName = filePath;
                if (filePath.contains('/')) {
                    fileName = filePath.section('/', -1);
                }
                
                QVariantMap fileInfo;
                fileInfo["path"] = filePath;
                fileInfo["name"] = fileName;
                fileInfo["status"] = "added";
                fileInfo["staged"] = false;
                m_changedFiles.append(fileInfo);
            }
        }
        
        emit changedFilesChanged();
        emit stagedFilesChanged();
        return;
    }

    // Try UTF-8 first, then local encoding (GBK on Chinese Windows)
    QString statusOutput = QString::fromUtf8(rawOutput);
    if (statusOutput.contains(QChar::ReplacementCharacter)) {
        statusOutput = QString::fromLocal8Bit(rawOutput);
    }
    
    QStringList lines = statusOutput.split('\n', Qt::SkipEmptyParts);
    
    for (int i = 0; i < lines.size(); i++) {
        QString line = lines[i];
        
        if (line.length() < 4) continue;
        
        QChar indexStatus = line[0];
        QChar workTreeStatus = line[1];
        QString filePath = line.mid(3);
        
        // Handle quoted paths with octal escapes (for paths Git still escapes)
        if (filePath.startsWith('"') && filePath.endsWith('"')) {
            filePath = decodeOctalEscapes(filePath);
        }

        // Handle renamed files: "old -> new"
        if (filePath.contains(" -> ")) {
            filePath = filePath.split(" -> ").last();
        }

        if (filePath.isEmpty()) continue;

        // Extract filename from path
        QString fileName = filePath;
        if (filePath.contains('/')) {
            fileName = filePath.section('/', -1);
        }

        QVariantMap fileInfo;
        fileInfo["path"] = filePath;
        fileInfo["name"] = fileName;

        // Determine status type
        QString statusType;
        if (indexStatus == 'A' || workTreeStatus == '?') {
            statusType = "added";
        } else if (indexStatus == 'D' || workTreeStatus == 'D') {
            statusType = "deleted";
        } else if (indexStatus == 'R') {
            statusType = "renamed";
        } else {
            statusType = "modified";
        }
        fileInfo["status"] = statusType;

        // Staged files
        if (indexStatus != ' ' && indexStatus != '?') {
            QVariantMap stagedInfo = fileInfo;
            stagedInfo["staged"] = true;
            m_stagedFiles.append(stagedInfo);
        }

        // Unstaged files
        if (workTreeStatus != ' ') {
            QVariantMap unstagedInfo = fileInfo;
            unstagedInfo["staged"] = false;
            m_changedFiles.append(unstagedInfo);
        }
    }

    emit changedFilesChanged();
    emit stagedFilesChanged();
}

void GitManager::parseStatusAsync(bool showLoading)
{
    QString repoPath = m_repoPath;
    
    if (showLoading) {
        setLoading(true);
        // Add timeout protection only when showing loading
        QTimer::singleShot(10000, this, [this]() {
            if (m_isLoading) {
                qDebug() << "parseStatusAsync timeout, forcing setLoading(false)";
                setLoading(false);
            }
        });
    }
    
    QFuture<void> future = QtConcurrent::run([this, repoPath, showLoading]() {
        // Set core.quotepath to false to show Chinese paths without escaping
        QProcess configProcess;
        configProcess.setWorkingDirectory(repoPath);
        configProcess.start("git", {"config", "core.quotepath", "false"});
        configProcess.waitForFinished(5000);
        
        QProcess process;
        process.setWorkingDirectory(repoPath);
        process.start("git", {"status", "--porcelain=v1", "-uall"});
        process.waitForFinished(30000);
        
        QByteArray rawOutput = process.readAllStandardOutput();
        
        QVariantList changedFiles;
        QVariantList stagedFiles;

        // If git status returns empty, try to find untracked files manually
        if (rawOutput.isEmpty() || rawOutput.trimmed().isEmpty()) {
            // Use git ls-files to find untracked files
            process.start("git", {"ls-files", "--others", "--exclude-standard"});
            process.waitForFinished(30000);
            QByteArray untrackedOutput = process.readAllStandardOutput();
            
            if (!untrackedOutput.isEmpty()) {
                // Try UTF-8 first, then local encoding
                QString untrackedStr = QString::fromUtf8(untrackedOutput);
                if (untrackedStr.contains(QChar::ReplacementCharacter)) {
                    untrackedStr = QString::fromLocal8Bit(untrackedOutput);
                }
                QStringList untrackedFiles = untrackedStr.split('\n', Qt::SkipEmptyParts);
                
                for (const QString &filePath : untrackedFiles) {
                    if (filePath.isEmpty()) continue;
                    
                    QString fileName = filePath;
                    if (filePath.contains('/')) {
                        fileName = filePath.section('/', -1);
                    }
                    
                    QVariantMap fileInfo;
                    fileInfo["path"] = filePath;
                    fileInfo["name"] = fileName;
                    fileInfo["status"] = "added";
                    fileInfo["staged"] = false;
                    
                    // Add file size
                    QFileInfo fileInfoObj(repoPath + "/" + filePath);
                    if (fileInfoObj.exists()) {
                        qint64 size = fileInfoObj.size();
                        fileInfo["size"] = size;
                        fileInfo["sizeStr"] = formatFileSize(size);
                    } else {
                        fileInfo["size"] = 0;
                        fileInfo["sizeStr"] = "0 B";
                    }
                    
                    changedFiles.append(fileInfo);
                }
            }
        } else {
            // Try UTF-8 first, then local encoding
            QString output = QString::fromUtf8(rawOutput);
            if (output.contains(QChar::ReplacementCharacter)) {
                output = QString::fromLocal8Bit(rawOutput);
            }
            
            QStringList lines = output.split('\n', Qt::SkipEmptyParts);
            
            for (const QString &line : lines) {
                if (line.length() < 3) continue;
                
                char indexStatus = line[0].toLatin1();
                char workTreeStatus = line[1].toLatin1();
                QString filePath = line.mid(3);
                
                // Handle renamed files (format: "R  old -> new")
                if (filePath.contains(" -> ")) {
                    filePath = filePath.section(" -> ", -1);
                }
                
                // Decode octal escapes for Chinese file names
                filePath = decodeOctalEscapes(filePath);
                
                QString fileName = filePath;
                if (filePath.contains('/')) {
                    fileName = filePath.section('/', -1);
                }
                
                QString status;
                if (indexStatus == 'A' || workTreeStatus == 'A') status = "added";
                else if (indexStatus == 'M' || workTreeStatus == 'M') status = "modified";
                else if (indexStatus == 'D' || workTreeStatus == 'D') status = "deleted";
                else if (indexStatus == 'R') status = "renamed";
                else if (indexStatus == '?' || workTreeStatus == '?') status = "untracked";
                else status = "modified";
                
                QVariantMap fileInfo;
                fileInfo["path"] = filePath;
                fileInfo["name"] = fileName;
                fileInfo["status"] = status;
                
                // Add file size
                QFileInfo fileInfoObj(repoPath + "/" + filePath);
                if (fileInfoObj.exists() && status != "deleted") {
                    qint64 size = fileInfoObj.size();
                    fileInfo["size"] = size;
                    fileInfo["sizeStr"] = formatFileSize(size);
                } else {
                    fileInfo["size"] = 0;
                    fileInfo["sizeStr"] = status == "deleted" ? "已删除" : "0 B";
                }
                
                // Staged files
                if (indexStatus != ' ' && indexStatus != '?') {
                    QVariantMap stagedInfo = fileInfo;
                    stagedInfo["staged"] = true;
                    stagedFiles.append(stagedInfo);
                }
                
                // Unstaged files
                if (workTreeStatus != ' ') {
                    QVariantMap unstagedInfo = fileInfo;
                    unstagedInfo["staged"] = false;
                    changedFiles.append(unstagedInfo);
                }
            }
        }
        
        // Update the lists in the main thread
        QMetaObject::invokeMethod(this, [this, changedFiles, stagedFiles, showLoading]() {
            m_changedFiles = changedFiles;
            m_stagedFiles = stagedFiles;
            emit changedFilesChanged();
            emit stagedFilesChanged();
            if (showLoading) {
                setLoading(false);
            }
        }, Qt::QueuedConnection);
    });
}

void GitManager::stageFile(const QString &filePath)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    QString fullPath = repoPath + "/" + filePath;
    bool fileExists = QFileInfo(fullPath).exists();
    
    QFuture<QPair<bool, QString>> future = QtConcurrent::run([repoPath, filePath, fileExists]() -> QPair<bool, QString> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        if (fileExists) {
            process.start("git", {"add", "--", filePath});
            process.waitForFinished(60000);
        } else {
            process.start("git", {"add", "-u", "--", filePath});
            process.waitForFinished(60000);
            
            if (process.exitCode() != 0) {
                process.start("git", {"rm", "--", filePath});
                process.waitForFinished(60000);
            }
        }
        
        if (process.exitCode() != 0) {
            QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
            return qMakePair(false, err);
        }
        return qMakePair(true, QString());
    });
    
    QFutureWatcher<QPair<bool, QString>> *watcher = new QFutureWatcher<QPair<bool, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<bool, QString>>::finished, this, [this, watcher, filePath]() {
        auto result = watcher->result();
        if (result.first) {
            refresh();
            emit operationSuccess("已暂存: " + filePath);
        } else {
            setLoading(false);
            setError("暂存失败: " + result.second);
        }
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::stageFiles(const QStringList &filePaths)
{
    if (m_repoPath.isEmpty() || filePaths.isEmpty()) return;
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    
    QFuture<QPair<bool, QString>> future = QtConcurrent::run([repoPath, filePaths]() -> QPair<bool, QString> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        QStringList args = {"add", "--"};
        args.append(filePaths);
        
        process.start("git", args);
        process.waitForFinished(120000);
        
        if (process.exitCode() != 0) {
            QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
            return qMakePair(false, err);
        }
        return qMakePair(true, QString());
    });
    
    QFutureWatcher<QPair<bool, QString>> *watcher = new QFutureWatcher<QPair<bool, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<bool, QString>>::finished, this, [this, watcher, filePaths]() {
        auto result = watcher->result();
        if (result.first) {
            refresh();
            emit operationSuccess("已暂存 " + QString::number(filePaths.size()) + " 个文件");
        } else {
            setLoading(false);
            setError("暂存失败: " + result.second);
        }
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::unstageFile(const QString &filePath)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    
    QFuture<void> future = QtConcurrent::run([repoPath, filePath]() {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        process.start("git", {"reset", "HEAD", "--", filePath});
        process.waitForFinished(60000);
    });
    
    QFutureWatcher<void> *watcher = new QFutureWatcher<void>(this);
    connect(watcher, &QFutureWatcher<void>::finished, this, [this, watcher, filePath]() {
        refresh();
        emit operationSuccess("已取消暂存: " + filePath);
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::unstageFiles(const QStringList &filePaths)
{
    if (m_repoPath.isEmpty() || filePaths.isEmpty()) return;
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    
    QFuture<void> future = QtConcurrent::run([repoPath, filePaths]() {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        QStringList args = {"reset", "HEAD", "--"};
        args.append(filePaths);
        
        process.start("git", args);
        process.waitForFinished(120000);
    });
    
    QFutureWatcher<void> *watcher = new QFutureWatcher<void>(this);
    connect(watcher, &QFutureWatcher<void>::finished, this, [this, watcher, filePaths]() {
        refresh();
        emit operationSuccess("已取消暂存 " + QString::number(filePaths.size()) + " 个文件");
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::stageAll()
{
    if (m_repoPath.isEmpty()) return;
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    
    QFuture<QPair<bool, QString>> future = QtConcurrent::run([repoPath]() -> QPair<bool, QString> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        process.start("git", {"add", "-A"});
        process.waitForFinished(120000);
        
        if (process.exitCode() != 0) {
            QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
            return qMakePair(false, err);
        }
        return qMakePair(true, QString());
    });
    
    QFutureWatcher<QPair<bool, QString>> *watcher = new QFutureWatcher<QPair<bool, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<bool, QString>>::finished, this, [this, watcher]() {
        auto result = watcher->result();
        setBulkOperationMode(false);
        if (result.first) {
            refresh();
            emit operationSuccess("已暂存所有文件");
        } else {
            setLoading(false);
            setError("暂存失败: " + result.second);
        }
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::unstageAll()
{
    if (m_repoPath.isEmpty()) {
        setError("未选择仓库");
        return;
    }
    
    // Check if there are staged files first
    if (m_stagedFiles.isEmpty()) {
        setBulkOperationMode(false);
        emit operationSuccess("没有已暂存的文件");
        return;
    }
    
    setLoading(true);
    
    // For new repositories without commits, use 'git rm --cached .' instead of 'git reset HEAD'
    // First check if HEAD exists by checking if there are any commits
    QProcess checkProcess;
    checkProcess.setWorkingDirectory(m_repoPath);
    checkProcess.start("git", {"rev-parse", "--verify", "HEAD"});
    checkProcess.waitForFinished(5000);
    
    QStringList args;
    if (checkProcess.exitCode() == 0) {
        // HEAD exists, use normal reset
        args = {"reset", "HEAD"};
    } else {
        // No commits yet, use rm --cached to unstage all files
        args = {"rm", "--cached", "-r", "."};
    }
    
    // Use async process for better control
    if (m_asyncProcess->state() != QProcess::NotRunning) {
        setLoading(false);
        setBulkOperationMode(false);
        setError("有操作正在进行中，请稍候");
        return;
    }
    
    m_asyncSuccessMsg = "已取消暂存所有文件";
    m_asyncErrorPrefix = "取消暂存失败";
    
    m_asyncProcess->setWorkingDirectory(m_repoPath);
    m_asyncProcess->start("git", args);
}

void GitManager::commit(const QString &message)
{
    if (message.trimmed().isEmpty()) {
        setError("提交信息不能为空");
        return;
    }

    // Must have staged files to commit
    if (m_stagedFiles.isEmpty()) {
        setError("没有已暂存的文件，请先暂存要提交的文件");
        return;
    }

    setLoading(true);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    
    // Commit only the staged files
    process.start("git", {"commit", "-m", message});
    process.waitForFinished(30000);
    
    QString errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
    QString output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    
    qDebug() << "Commit exitCode:" << process.exitCode();
    qDebug() << "Commit stdout:" << output;
    qDebug() << "Commit stderr:" << errorOutput;
    
    int exitCode = process.exitCode();
    
    if (exitCode != 0) {
        setLoading(false);
        // Check for common errors
        if (errorOutput.contains("user.email") || errorOutput.contains("user.name") ||
            errorOutput.contains("Please tell me who you are")) {
            setError("请先配置 Git 用户信息:\ngit config user.name \"你的名字\"\ngit config user.email \"你的邮箱\"");
        } else if (errorOutput.contains("nothing to commit") || output.contains("nothing to commit")) {
            setError("没有需要提交的更改");
        } else if (errorOutput.isEmpty() && output.isEmpty()) {
            setError("提交失败 (exitCode: " + QString::number(exitCode) + ")");
        } else {
            setError("提交失败: " + (errorOutput.isEmpty() ? output : errorOutput));
        }
        return;
    }
    
    setLoading(false);
    emit operationSuccess("提交成功");
    refresh();
}

void GitManager::push()
{
    setLoading(true);
    
    // First check if there's a remote
    QString remote = runGitCommand({"remote"});
    if (remote.isEmpty()) {
        setError("未配置远程仓库");
        setLoading(false);
        return;
    }

    // Run push asynchronously
    runAsyncGitCommand({"push", "-u", "origin", m_currentBranch}, "推送成功", "推送失败");
}

void GitManager::quickSync(const QString &message)
{
    if (message.trimmed().isEmpty()) {
        setError("请输入提交信息");
        return;
    }

    setLoading(true);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    
    // Step 1: Stage all changes (quick operation)
    process.start("git", {"add", "-A"});
    process.waitForFinished(30000);
    
    if (process.exitCode() != 0) {
        setLoading(false);
        QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
        setError("暂存失败: " + err);
        return;
    }
    
    // Step 2: Check if there's anything to commit (quick operation)
    process.start("git", {"status", "--porcelain"});
    process.waitForFinished(30000);
    QString statusOutput = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    
    if (statusOutput.isEmpty()) {
        setLoading(false);
        setError("没有需要提交的更改");
        return;
    }
    
    // Step 3: Commit (quick operation)
    process.start("git", {"commit", "-m", message});
    process.waitForFinished(30000);
    
    QString commitError = QString::fromUtf8(process.readAllStandardError()).trimmed();
    QString commitOutput = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    int commitExitCode = process.exitCode();
    
    if (commitExitCode != 0) {
        if (commitError.contains("nothing to commit") || commitOutput.contains("nothing to commit")) {
            setLoading(false);
            setError("没有需要提交的更改");
            return;
        }
        if (commitError.contains("user.email") || commitError.contains("user.name") ||
            commitError.contains("Please tell me who you are")) {
            setLoading(false);
            setError("请先配置 Git 用户信息:\ngit config user.name \"你的名字\"\ngit config user.email \"你的邮箱\"");
            return;
        }
        setLoading(false);
        setError("提交失败: " + (commitError.isEmpty() ? commitOutput : commitError));
        return;
    }
    
    // Step 4: Push asynchronously (this is the slow part)
    runAsyncGitCommand({"push", "-u", "origin", m_currentBranch}, "同步成功！已提交并推送到远程", "提交成功，但推送失败");
}

void GitManager::pull()
{
    setLoading(true);
    // Run pull asynchronously
    runAsyncGitCommand({"pull"}, "拉取成功", "拉取失败");
}

void GitManager::switchBranch(const QString &branchName)
{
    setLoading(true);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"checkout", branchName});
    process.waitForFinished(30000);
    
    QString errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
    
    if (process.exitCode() != 0) {
        setLoading(false);
        if (errorOutput.contains("uncommitted changes") || errorOutput.contains("would be overwritten")) {
            setError("切换失败：有未提交的更改，请先提交或撤销");
        } else if (errorOutput.contains("did not match")) {
            // Try to checkout remote branch
            process.start("git", {"checkout", "-b", branchName, "origin/" + branchName});
            process.waitForFinished(30000);
            if (process.exitCode() != 0) {
                setError("切换失败: " + errorOutput);
                return;
            }
        } else {
            setError("切换失败: " + errorOutput);
            return;
        }
    }
    
    // Update current branch
    m_currentBranch = runGitCommand({"branch", "--show-current"});
    emit currentBranchChanged();
    
    // Update branch list
    updateBranches();
    parseStatus();
    
    setLoading(false);
    emit operationSuccess("已切换到分支: " + m_currentBranch);
}

void GitManager::createBranch(const QString &branchName)
{
    if (branchName.trimmed().isEmpty()) {
        setError("分支名称不能为空");
        return;
    }

    setLoading(true);
    
    // Create and switch to new branch (local operation, fast)
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"checkout", "-b", branchName});
    process.waitForFinished(30000);

    // Check if we're now on the new branch
    QString currentBranch = runGitCommand({"branch", "--show-current"});
    
    if (currentBranch == branchName) {
        // Update current branch immediately
        m_currentBranch = branchName;
        emit currentBranchChanged();
        
        // Force update branch list
        updateBranches();
        
        // Push new branch to remote - async
        runAsyncGitCommand({"push", "-u", "origin", branchName}, 
                           "已创建分支并推送到远程: " + branchName,
                           "已创建本地分支，但推送失败");
    } else {
        QString errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
        setLoading(false);
        setError("创建分支失败: " + errorOutput);
    }
}

void GitManager::deleteBranch(const QString &branchName)
{
    if (branchName == m_currentBranch) {
        setError("不能删除当前所在分支");
        return;
    }

    setLoading(true);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    
    bool isLocal = m_localBranches.contains(branchName);
    bool isRemote = m_remoteBranches.contains(branchName);
    
    int exitCode = 0;
    QString errorOutput;
    
    // Delete local branch if exists
    if (isLocal) {
        process.start("git", {"branch", "-D", branchName});
        process.waitForFinished(30000);
        exitCode = process.exitCode();
        errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
    }
    
    // Delete remote branch if exists
    if (isRemote || isLocal) {
        // Also try to delete from remote
        process.start("git", {"push", "origin", "--delete", branchName});
        process.waitForFinished(60000);
        // Don't fail if remote delete fails (branch might not exist on remote)
        if (process.exitCode() != 0 && !isLocal) {
            exitCode = process.exitCode();
            errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
        }
    }

    // Update branch list
    updateBranches();
    setLoading(false);
    
    if (exitCode == 0 || (!m_localBranches.contains(branchName) && !m_remoteBranches.contains(branchName))) {
        emit operationSuccess("已删除分支: " + branchName);
    } else {
        setError("删除分支失败: " + errorOutput);
    }
}

void GitManager::mergeBranch(const QString &branchName)
{
    if (branchName == m_currentBranch) {
        setError("不能合并当前分支到自己");
        return;
    }

    setLoading(true);
    
    QString repoPath = m_repoPath;
    QString currentBranch = m_currentBranch;
    
    QFuture<QPair<int, QString>> future = QtConcurrent::run([repoPath, branchName, currentBranch]() -> QPair<int, QString> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        // First fetch to make sure we have latest refs
        process.start("git", {"fetch", "--all"});
        process.waitForFinished(60000);
        
        // Try to merge remote branch first (origin/branchName), fall back to local
        QString mergeBranch = "origin/" + branchName;
        
        // Check if remote branch exists
        process.start("git", {"rev-parse", "--verify", mergeBranch});
        process.waitForFinished(5000);
        if (process.exitCode() != 0) {
            // Remote branch doesn't exist, use local
            mergeBranch = branchName;
        }
        
        // Merge the specified branch into current branch
        process.start("git", {"merge", mergeBranch, "-m", "合并分支 " + branchName + " 到 " + currentBranch});
        process.waitForFinished(120000);
        
        QString errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
        QString output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        int exitCode = process.exitCode();
        
        QString result = errorOutput.isEmpty() ? output : errorOutput;
        
        bool alreadyUpToDate = output.contains("Already up to date") || output.contains("Already up-to-date");
        
        if (exitCode != 0 && !alreadyUpToDate) {
            return qMakePair(exitCode, result);
        }
        
        // Check if there are unpushed commits
        process.start("git", {"log", "origin/" + currentBranch + ".." + currentBranch, "--oneline"});
        process.waitForFinished(10000);
        QString unpushed = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        
        if (unpushed.isEmpty() && alreadyUpToDate) {
            // Really nothing to do
            return qMakePair(100, QString("already_up_to_date"));
        }
        
        // Push (either merge result or existing unpushed commits)
        process.start("git", {"push", "-u", "origin", currentBranch});
        process.waitForFinished(120000);
        
        if (process.exitCode() != 0) {
            QString pushError = QString::fromUtf8(process.readAllStandardError()).trimmed();
            // Check if it's because remote has changes
            if (pushError.contains("rejected") || pushError.contains("failed to push")) {
                return qMakePair(201, pushError);  // Need force push
            }
            return qMakePair(200, pushError);  // Other push failure
        }
        
        if (alreadyUpToDate) {
            return qMakePair(101, QString("pushed_existing"));  // Pushed existing commits
        }
        
        return qMakePair(0, QString("success"));
    });
    
    QFutureWatcher<QPair<int, QString>> *watcher = new QFutureWatcher<QPair<int, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<int, QString>>::finished, this, [this, watcher, branchName]() {
        auto result = watcher->result();
        int code = result.first;
        QString msg = result.second;
        
        setLoading(false);
        
        if (code == 0) {
            refresh();
            emit operationSuccess("已将 " + branchName + " 合并到 " + m_currentBranch + " 并推送到远程");
        } else if (code == 100) {
            refresh();
            emit operationSuccess("分支已是最新，无需合并");
        } else if (code == 101) {
            refresh();
            emit operationSuccess("已推送本地提交到远程");
        } else if (code == 200) {
            refresh();
            setError("合并成功，但推送失败: " + msg);
        } else if (code == 201) {
            refresh();
            setError("推送被拒绝：远程有更新，请先拉取或使用强制推送");
        } else {
            if (msg.contains("CONFLICT")) {
                setError("合并冲突！请手动解决冲突后提交");
            } else if (msg.contains("uncommitted changes")) {
                setError("有未提交的更改，请先提交或撤销");
            } else {
                setError("合并失败: " + msg);
            }
        }
        
        watcher->deleteLater();
    });
    
    watcher->setFuture(future);
}

void GitManager::discardChanges(const QString &filePath)
{
    setLoading(true);
    runGitCommand({"checkout", "--", filePath});
    refresh();
    emit operationSuccess("已撤销更改: " + filePath);
}

void GitManager::discardAllChanges()
{
    setLoading(true);
    // Discard all changes in tracked files
    runGitCommand({"checkout", "--", "."});
    // Remove untracked files
    runGitCommand({"clean", "-fd"});
    refresh();
    setBulkOperationMode(false);
    emit operationSuccess("已撤销所有更改");
}

void GitManager::deleteNewFile(const QString &filePath)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;
    
    QString fullPath = m_repoPath + "/" + filePath;
    QFile file(fullPath);
    
    if (file.exists()) {
        if (file.remove()) {
            refresh();
            emit operationSuccess("已删除文件: " + filePath);
        } else {
            setError("删除文件失败: " + filePath);
        }
    } else {
        setError("文件不存在: " + filePath);
    }
}

void GitManager::addToGitignore(const QString &pattern)
{
    if (m_repoPath.isEmpty() || pattern.isEmpty()) return;
    
    QString gitignorePath = m_repoPath + "/.gitignore";
    QFile file(gitignorePath);
    
    // Read existing content
    QString existingContent;
    if (file.exists()) {
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            existingContent = QString::fromUtf8(file.readAll());
            file.close();
            
            // Check if pattern already exists
            QStringList lines = existingContent.split('\n');
            for (const QString &line : lines) {
                if (line.trimmed() == pattern.trimmed()) {
                    emit operationSuccess("该规则已存在于 .gitignore");
                    return;
                }
            }
        }
    }
    
    // Append new pattern
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        // Add newline if file doesn't end with one
        if (!existingContent.isEmpty() && !existingContent.endsWith('\n')) {
            stream << "\n";
        }
        stream << pattern << "\n";
        file.close();
        
        refresh();
        emit operationSuccess("已添加到 .gitignore: " + pattern);
    } else {
        setError("无法写入 .gitignore 文件");
    }
}

QStringList GitManager::getGitignoreRules()
{
    QStringList rules;
    if (m_repoPath.isEmpty()) return rules;
    
    QString gitignorePath = m_repoPath + "/.gitignore";
    QFile file(gitignorePath);
    
    if (file.exists() && file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString content = QString::fromUtf8(file.readAll());
        file.close();
        
        QStringList lines = content.split('\n');
        for (const QString &line : lines) {
            QString trimmed = line.trimmed();
            // Skip empty lines and comments
            if (!trimmed.isEmpty() && !trimmed.startsWith('#')) {
                rules.append(trimmed);
            }
        }
    }
    
    return rules;
}

void GitManager::removeFromGitignore(const QString &pattern)
{
    if (m_repoPath.isEmpty() || pattern.isEmpty()) return;
    
    QString gitignorePath = m_repoPath + "/.gitignore";
    QFile file(gitignorePath);
    
    if (!file.exists()) {
        setError(".gitignore 文件不存在");
        return;
    }
    
    // Read existing content
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        setError("无法读取 .gitignore 文件");
        return;
    }
    
    QString content = QString::fromUtf8(file.readAll());
    file.close();
    
    // Remove the pattern
    QStringList lines = content.split('\n');
    QStringList newLines;
    bool found = false;
    
    for (const QString &line : lines) {
        if (line.trimmed() == pattern.trimmed()) {
            found = true;
            continue;  // Skip this line
        }
        newLines.append(line);
    }
    
    if (!found) {
        emit operationSuccess("规则不存在于 .gitignore");
        return;
    }
    
    // Write back
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        setError("无法写入 .gitignore 文件");
        return;
    }
    
    QTextStream stream(&file);
    stream << newLines.join('\n');
    file.close();
    
    refresh();
    emit operationSuccess("已从 .gitignore 移除: " + pattern);
}

void GitManager::abortMerge()
{
    if (m_repoPath.isEmpty()) return;
    
    setLoading(true);
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"merge", "--abort"});
    process.waitForFinished(30000);
    
    if (process.exitCode() != 0) {
        // Try reset if merge --abort fails
        process.start("git", {"reset", "--hard", "HEAD"});
        process.waitForFinished(30000);
    }
    
    setLoading(false);
    refresh();
    emit operationSuccess("已取消合并");
}

void GitManager::resetToBranch(const QString &branchName)
{
    if (m_repoPath.isEmpty() || branchName.isEmpty()) return;
    if (branchName == m_currentBranch) {
        setError("不能重置到当前分支");
        return;
    }
    
    setLoading(true);
    
    QString repoPath = m_repoPath;
    QString currentBranch = m_currentBranch;
    
    QFuture<QPair<bool, QString>> future = QtConcurrent::run([repoPath, branchName, currentBranch]() -> QPair<bool, QString> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        // Fetch latest
        process.start("git", {"fetch", "--all"});
        process.waitForFinished(60000);
        
        // Try remote branch first
        QString targetBranch = "origin/" + branchName;
        process.start("git", {"rev-parse", "--verify", targetBranch});
        process.waitForFinished(5000);
        if (process.exitCode() != 0) {
            targetBranch = branchName;
        }
        
        // Reset current branch to target branch
        process.start("git", {"reset", "--hard", targetBranch});
        process.waitForFinished(60000);
        
        if (process.exitCode() != 0) {
            QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
            return qMakePair(false, err);
        }
        
        // Force push to update remote
        process.start("git", {"push", "--force", "origin", currentBranch});
        process.waitForFinished(120000);
        
        if (process.exitCode() != 0) {
            QString err = QString::fromUtf8(process.readAllStandardError()).trimmed();
            return qMakePair(false, QString("重置成功，但推送失败: ") + err);
        }
        
        return qMakePair(true, QString());
    });
    
    QFutureWatcher<QPair<bool, QString>> *watcher = new QFutureWatcher<QPair<bool, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<bool, QString>>::finished, this, [this, watcher, branchName]() {
        auto result = watcher->result();
        setLoading(false);
        refresh();
        
        if (result.first) {
            emit operationSuccess("已将当前分支重置为 " + branchName + " 的内容并推送");
        } else {
            setError(result.second);
        }
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::cloneRepo(const QString &url, const QString &targetPath)
{
    if (url.trimmed().isEmpty()) {
        setError("仓库地址不能为空");
        return;
    }

    QString cleanPath = targetPath;
    if (cleanPath.startsWith("file:///")) {
        cleanPath = cleanPath.mid(8);
    }

    if (cleanPath.isEmpty()) {
        setError("请选择目标文件夹");
        return;
    }

    // Extract repo name from URL
    QString repoName = url.split('/').last();
    if (repoName.endsWith(".git")) {
        repoName = repoName.chopped(4);
    }
    m_cloneTargetPath = cleanPath + "/" + repoName;

    setLoading(true);
    setError("");

    // Run clone asynchronously
    if (m_asyncProcess->state() != QProcess::NotRunning) {
        setLoading(false);
        setError("有操作正在进行中，请稍候");
        return;
    }
    
    m_asyncSuccessMsg = "克隆成功";
    m_asyncErrorPrefix = "克隆失败";
    
    m_asyncProcess->setWorkingDirectory(cleanPath);
    m_asyncProcess->start("git", {"clone", url});
}

QVariantList GitManager::repoFiles() const
{
    return m_repoFiles;
}

QString GitManager::currentPath() const
{
    return m_currentPath;
}

QString GitManager::fileContent() const
{
    return m_fileContent;
}

void GitManager::loadRepoFiles(const QString &subPath)
{
    if (m_repoPath.isEmpty()) return;

    m_currentPath = subPath;
    emit currentPathChanged();

    QString fullPath = m_repoPath;
    if (!subPath.isEmpty()) {
        fullPath += "/" + subPath;
    }

    QDir dir(fullPath);
    if (!dir.exists()) {
        setError("目录不存在");
        return;
    }

    m_repoFiles.clear();

    // Get all entries
    QFileInfoList entries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot, QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &info : entries) {
        // Skip .git folder
        if (info.fileName() == ".git") continue;

        QVariantMap fileInfo;
        fileInfo["name"] = info.fileName();
        fileInfo["path"] = subPath.isEmpty() ? info.fileName() : subPath + "/" + info.fileName();
        fileInfo["isDir"] = info.isDir();
        fileInfo["size"] = info.size();
        fileInfo["modified"] = info.lastModified().toString("yyyy-MM-dd hh:mm");

        m_repoFiles.append(fileInfo);
    }

    emit repoFilesChanged();
}

void GitManager::openFile(const QString &filePath)
{
    if (m_repoPath.isEmpty()) return;

    QString fullPath = m_repoPath + "/" + filePath;
    QFileInfo fileInfo(fullPath);
    
    // Check file size - warn if too large (> 1MB)
    qint64 fileSize = fileInfo.size();
    if (fileSize > 1024 * 1024) {
        setError("文件太大 (" + QString::number(fileSize / 1024 / 1024.0, 'f', 1) + " MB)，不建议在此编辑");
        m_fileContent = "";
        emit fileContentChanged();
        return;
    }
    
    // Check if it's a binary file by extension
    QString suffix = fileInfo.suffix().toLower();
    QStringList binaryExtensions = {"exe", "dll", "so", "dylib", "bin", "dat",
                                     "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp",
                                     "mp3", "mp4", "avi", "mov", "mkv", "wav", "flac",
                                     "zip", "rar", "7z", "tar", "gz", "bz2",
                                     "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                                     "ttf", "otf", "woff", "woff2"};
    if (binaryExtensions.contains(suffix)) {
        setError("这是二进制文件，无法编辑");
        m_fileContent = "";
        emit fileContentChanged();
        return;
    }

    setLoading(true);
    
    QFile file(fullPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        setLoading(false);
        setError("无法打开文件");
        return;
    }

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);
    m_fileContent = in.readAll();
    file.close();

    setLoading(false);
    emit fileContentChanged();
}

void GitManager::openFileLocation(const QString &filePath)
{
    if (m_repoPath.isEmpty()) return;

    QString fullPath = m_repoPath + "/" + filePath;
    QFileInfo fileInfo(fullPath);
    QString folderPath = fileInfo.absolutePath();

    // Windows: use explorer to open folder and select file
    #ifdef Q_OS_WIN
    QProcess::startDetached("explorer", {"/select,", QDir::toNativeSeparators(fileInfo.absoluteFilePath())});
    #elif defined(Q_OS_MAC)
    QProcess::startDetached("open", {"-R", fileInfo.absoluteFilePath()});
    #else
    QDesktopServices::openUrl(QUrl::fromLocalFile(folderPath));
    #endif
}

QVariantList GitManager::getFileDiff(const QString &filePath, bool staged)
{
    QVariantList diffLines;
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return diffLines;
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    
    // Get diff: staged uses --cached, unstaged doesn't
    QStringList args;
    if (staged) {
        args = {"diff", "--cached", "--", filePath};
    } else {
        args = {"diff", "--", filePath};
    }
    
    process.start("git", args);
    process.waitForFinished(30000);
    
    QString output = QString::fromUtf8(process.readAllStandardOutput());
    
    if (output.isEmpty()) {
        // For new files, show all content as added
        if (!staged) {
            // Check if it's a new untracked file
            QString fullPath = m_repoPath + "/" + filePath;
            QFile file(fullPath);
            if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QTextStream in(&file);
                in.setEncoding(QStringConverter::Utf8);
                QString content = in.readAll();
                file.close();
                
                QStringList lines = content.split('\n');
                for (int i = 0; i < lines.size(); i++) {
                    QVariantMap line;
                    line["type"] = "add";
                    line["content"] = lines[i];
                    line["lineNum"] = i + 1;
                    diffLines.append(line);
                }
            }
        }
        return diffLines;
    }
    
    // Parse diff output
    QStringList lines = output.split('\n');
    int oldLineNum = 0;
    int newLineNum = 0;
    
    for (const QString &line : lines) {
        // Skip diff header lines
        if (line.startsWith("diff --git") || line.startsWith("index ") ||
            line.startsWith("---") || line.startsWith("+++")) {
            continue;
        }
        
        QVariantMap diffLine;
        
        if (line.startsWith("@@")) {
            // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
            QRegularExpression re("@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@");
            QRegularExpressionMatch match = re.match(line);
            if (match.hasMatch()) {
                oldLineNum = match.captured(1).toInt();
                newLineNum = match.captured(2).toInt();
            }
            diffLine["type"] = "header";
            diffLine["content"] = line;
            diffLine["lineNum"] = 0;
        }
        else if (line.startsWith("-")) {
            diffLine["type"] = "delete";
            diffLine["content"] = line.mid(1);
            diffLine["lineNum"] = oldLineNum++;
        }
        else if (line.startsWith("+")) {
            diffLine["type"] = "add";
            diffLine["content"] = line.mid(1);
            diffLine["lineNum"] = newLineNum++;
        }
        else if (line.startsWith(" ")) {
            diffLine["type"] = "context";
            diffLine["content"] = line.mid(1);
            diffLine["lineNum"] = newLineNum++;
            oldLineNum++;
        }
        else {
            continue;
        }
        
        diffLines.append(diffLine);
    }
    
    return diffLines;
}

void GitManager::saveFile(const QString &filePath, const QString &content)
{
    if (m_repoPath.isEmpty()) return;

    QString fullPath = m_repoPath + "/" + filePath;
    QFile file(fullPath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setError("无法保存文件");
        return;
    }

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << content;
    file.close();

    emit operationSuccess("文件已保存");
    refresh();
}

void GitManager::deleteRepoFile(const QString &filePath)
{
    if (m_repoPath.isEmpty()) return;

    QString fullPath = m_repoPath + "/" + filePath;
    QFileInfo info(fullPath);

    bool success = false;
    if (info.isDir()) {
        QDir dir(fullPath);
        success = dir.removeRecursively();
    } else {
        success = QFile::remove(fullPath);
    }

    if (success) {
        emit operationSuccess("已删除: " + filePath);
        loadRepoFiles(m_currentPath);
        refresh();
    } else {
        setError("删除失败");
    }
}

void GitManager::goBack()
{
    if (m_currentPath.isEmpty()) return;

    int lastSlash = m_currentPath.lastIndexOf('/');
    if (lastSlash > 0) {
        loadRepoFiles(m_currentPath.left(lastSlash));
    } else {
        loadRepoFiles("");
    }
}

QVariantList GitManager::remoteFiles() const
{
    return m_remoteFiles;
}

QString GitManager::remoteCurrentPath() const
{
    return m_remoteCurrentPath;
}

QString GitManager::remoteUrl() const
{
    return m_remoteUrl;
}

void GitManager::loadRemoteFiles(const QString &subPath)
{
    if (m_repoPath.isEmpty()) return;

    setLoading(true);
    m_remoteCurrentPath = subPath;
    emit remoteCurrentPathChanged();

    QString repoPath = m_repoPath;
    QString currentBranch = m_currentBranch;
    
    QFuture<QPair<QString, QVariantList>> future = QtConcurrent::run([repoPath, subPath, currentBranch]() -> QPair<QString, QVariantList> {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        QVariantList files;
        
        // Get remote URL
        process.start("git", {"remote", "get-url", "origin"});
        process.waitForFinished(10000);
        QString remoteUrl = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        
        // Fetch latest from remote
        process.start("git", {"fetch", "origin"});
        process.waitForFinished(60000);
        
        // Use git ls-tree to list files from remote branch
        QString remoteBranch = "origin/" + currentBranch;
        
        QStringList args;
        if (subPath.isEmpty()) {
            args = {"ls-tree", "-l", remoteBranch};
        } else {
            args = {"ls-tree", "-l", remoteBranch, subPath + "/"};
        }
        
        process.start("git", args);
        process.waitForFinished(30000);
        QString detailOutput = QString::fromUtf8(process.readAllStandardOutput());
        
        // Parse ls-tree output
        QStringList lines = detailOutput.split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            QRegularExpression re("^(\\d+)\\s+(\\w+)\\s+(\\w+)\\s+(\\S+)\\s+(.+)$");
            QRegularExpressionMatch match = re.match(line);
            
            if (match.hasMatch()) {
                QString type = match.captured(2);
                QString size = match.captured(4);
                QString fullPath = match.captured(5);
                
                // Decode octal escapes - use the class method
                fullPath = GitManager::decodeOctalEscapes(fullPath);
                
                QString name = fullPath;
                if (fullPath.contains('/')) {
                    name = fullPath.section('/', -1);
                }
                
                QVariantMap fileInfo;
                fileInfo["name"] = name;
                fileInfo["path"] = fullPath;
                fileInfo["isDir"] = (type == "tree");
                fileInfo["size"] = (size == "-") ? 0 : size.toLongLong();
                fileInfo["type"] = type;
                
                // Get last commit info with full time
                process.start("git", {"log", "-1", "--format=%s|%ar|%ci", remoteBranch, "--", fullPath});
                process.waitForFinished(5000);
                QString logOutput = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
                if (!logOutput.isEmpty()) {
                    QStringList logParts = logOutput.split('|');
                    if (logParts.size() >= 3) {
                        fileInfo["commitMsg"] = logParts[0].trimmed();
                        fileInfo["commitTimeRelative"] = logParts[1].trimmed();
                        // Parse full time: 2025-01-16 14:30:00 +0800 -> 2025-01-16 14:30
                        QString fullTime = logParts[2].trimmed();
                        if (fullTime.length() >= 16) {
                            fileInfo["commitTimeFull"] = fullTime.left(16);
                        } else {
                            fileInfo["commitTimeFull"] = fullTime;
                        }
                    } else if (logParts.size() >= 2) {
                        fileInfo["commitMsg"] = logParts[0].trimmed();
                        fileInfo["commitTimeRelative"] = logParts[1].trimmed();
                    }
                }
                
                files.append(fileInfo);
            }
        }
        
        return qMakePair(remoteUrl, files);
    });
    
    QFutureWatcher<QPair<QString, QVariantList>> *watcher = new QFutureWatcher<QPair<QString, QVariantList>>(this);
    connect(watcher, &QFutureWatcher<QPair<QString, QVariantList>>::finished, this, [this, watcher]() {
        auto result = watcher->result();
        m_remoteUrl = result.first;
        m_remoteFiles = result.second;
        emit remoteUrlChanged();
        emit remoteFilesChanged();
        setLoading(false);
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::goBackRemote()
{
    if (m_remoteCurrentPath.isEmpty()) return;

    int lastSlash = m_remoteCurrentPath.lastIndexOf('/');
    if (lastSlash > 0) {
        loadRemoteFiles(m_remoteCurrentPath.left(lastSlash));
    } else {
        loadRemoteFiles("");
    }
}

void GitManager::deleteRemoteFile(const QString &filePath, const QString &message)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;

    setLoading(true);

    // Delete file locally
    QString fullPath = m_repoPath + "/" + filePath;
    QFileInfo info(fullPath);
    
    if (info.isDir()) {
        QDir dir(fullPath);
        dir.removeRecursively();
    } else {
        QFile::remove(fullPath);
    }

    // Stage the deletion
    runGitCommand({"add", "-A"});

    // Commit
    QString commitMsg = message.isEmpty() ? "Delete " + filePath : message;
    runGitCommand({"commit", "-m", commitMsg});

    // Push to remote - async
    runAsyncGitCommand({"push", "origin", m_currentBranch}, 
                       "已删除并推送: " + filePath + "，请点击刷新查看",
                       "已删除，但推送失败");
}

void GitManager::saveAndPushFile(const QString &filePath, const QString &content, const QString &message)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;

    setLoading(true);

    // Save file locally
    QString fullPath = m_repoPath + "/" + filePath;
    QFile file(fullPath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setLoading(false);
        setError("无法保存文件");
        return;
    }

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << content;
    file.close();

    // Stage the file
    runGitCommand({"add", filePath});

    // Handle commit message
    QString commitMsg = message.trimmed();
    if (commitMsg.isEmpty()) {
        commitMsg = "Update " + filePath;
    }
    
    // Run git commit (local, fast)
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    
    process.start("git", QStringList() << "commit" << "-m" << commitMsg);
    process.waitForFinished(30000);
    
    int exitCode = process.exitCode();
    QString stdOut = QString::fromUtf8(process.readAllStandardOutput());
    QString stdErr = QString::fromUtf8(process.readAllStandardError());
    
    if (exitCode != 0) {
        if (stdErr.contains("nothing to commit") || stdOut.contains("nothing to commit")) {
            setLoading(false);
            setError("文件没有变化，无需提交");
            return;
        }
    }

    // Push to remote - async
    runAsyncGitCommand({"push", "origin", m_currentBranch}, 
                       "已保存并推送: " + filePath + "，请点击刷新查看",
                       "已保存，但推送失败");
}

void GitManager::renameRemoteFile(const QString &oldPath, const QString &newPath, const QString &message)
{
    if (m_repoPath.isEmpty() || oldPath.isEmpty() || newPath.isEmpty()) return;
    if (oldPath == newPath) {
        setError("新旧文件名相同");
        return;
    }

    setLoading(true);

    // Use git mv to rename the file
    QString result = runGitCommand({"mv", oldPath, newPath});
    
    // Commit the rename
    QString commitMsg = message.trimmed();
    if (commitMsg.isEmpty()) {
        commitMsg = "Rename " + oldPath + " to " + newPath;
    }
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"commit", "-m", commitMsg});
    process.waitForFinished(30000);

    // Push to remote - async
    // Store path for refresh after push
    QString currentRemotePath = m_remoteCurrentPath;
    runAsyncGitCommand({"push", "origin", m_currentBranch}, 
                       "已重命名: " + oldPath + " → " + newPath + "，请点击刷新查看",
                       "已重命名，但推送失败");
}

QVariantList GitManager::commitHistory() const
{
    return m_commitHistory;
}

QVariantMap GitManager::lastCommit() const
{
    if (m_commitHistory.isEmpty()) {
        return QVariantMap();
    }
    return m_commitHistory.first().toMap();
}

QStringList GitManager::lastCommitFiles() const
{
    if (m_repoPath.isEmpty()) return QStringList();
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"});
    process.waitForFinished(5000);
    
    QString output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    if (output.isEmpty()) return QStringList();
    
    return output.split("\n", Qt::SkipEmptyParts);
}

QString GitManager::lastCommitTime() const
{
    if (m_repoPath.isEmpty()) return QString();
    
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", {"log", "-1", "--format=%ci|%ar"});
    process.waitForFinished(5000);
    
    QString output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    if (output.isEmpty()) return QString();
    
    QStringList parts = output.split('|');
    if (parts.size() >= 2) {
        QString fullTime = parts[0].trimmed();
        QString relativeTime = parts[1].trimmed();
        // Format: 2025-01-16 22:30:00 +0800 -> 2025-01-16 22:30
        if (fullTime.length() >= 16) {
            return fullTime.left(16) + " (" + relativeTime + ")";
        }
        return fullTime + " (" + relativeTime + ")";
    }
    return output;
}

QString GitManager::userName() const
{
    return m_userName;
}

QString GitManager::userEmail() const
{
    return m_userEmail;
}

QString GitManager::userAvatar() const
{
    // Generate Gravatar URL from email
    if (m_userEmail.isEmpty()) {
        return "";
    }
    
    // Use Gravatar with email hash
    QString email = m_userEmail.toLower().trimmed();
    QByteArray hash = QCryptographicHash::hash(email.toUtf8(), QCryptographicHash::Md5);
    QString hashStr = hash.toHex();
    
    return "https://www.gravatar.com/avatar/" + hashStr + "?s=80&d=identicon";
}

void GitManager::loadCommitHistory()
{
    if (m_repoPath.isEmpty()) return;

    setLoading(true);
    
    QString repoPath = m_repoPath;
    
    QFuture<QVariantList> future = QtConcurrent::run([repoPath]() -> QVariantList {
        QVariantList history;
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        // Get commit history with detailed info
        process.start("git", {"log", "--pretty=format:%H|%an|%ar|%ci|%s", "-30"});
        process.waitForFinished(30000);
        QString output = QString::fromUtf8(process.readAllStandardOutput());
        
        QStringList commits = output.split('\n', Qt::SkipEmptyParts);
        
        for (const QString &commit : commits) {
            QStringList parts = commit.split('|');
            if (parts.size() >= 5) {
                QVariantMap commitInfo;
                commitInfo["hash"] = parts[0];
                commitInfo["shortHash"] = parts[0].left(7);
                commitInfo["author"] = parts[1];
                commitInfo["relativeDate"] = parts[2];
                
                QString fullDate = parts[3];
                if (fullDate.length() >= 19) {
                    QString dateOnly = fullDate.left(10);
                    QString timeOnly = fullDate.mid(11, 8);
                    commitInfo["fullDate"] = dateOnly + " " + timeOnly;
                    commitInfo["date"] = dateOnly;
                    commitInfo["time"] = timeOnly;
                } else {
                    commitInfo["fullDate"] = fullDate;
                    commitInfo["date"] = fullDate;
                    commitInfo["time"] = "";
                }
                
                commitInfo["message"] = parts.mid(4).join('|');
                
                // Get files changed in this commit
                process.start("git", {"diff-tree", "--no-commit-id", "--name-status", "-r", parts[0]});
                process.waitForFinished(10000);
                QString filesOutput = QString::fromUtf8(process.readAllStandardOutput());
                
                QVariantList fileChanges;
                QStringList fileLines = filesOutput.split('\n', Qt::SkipEmptyParts);
                for (const QString &fileLine : fileLines) {
                    if (fileLine.length() > 2) {
                        QVariantMap fileChange;
                        QString status = fileLine.left(1);
                        QString fileName = GitManager::decodeOctalEscapes(fileLine.mid(2).trimmed());
                        
                        fileChange["name"] = fileName;
                        fileChange["status"] = status;
                        
                        QString statusText;
                        if (status == "A") statusText = "添加";
                        else if (status == "M") statusText = "修改";
                        else if (status == "D") statusText = "删除";
                        else if (status == "R") statusText = "重命名";
                        else statusText = status;
                        fileChange["statusText"] = statusText;
                        
                        fileChanges.append(fileChange);
                    }
                }
                commitInfo["files"] = fileChanges;
                commitInfo["fileCount"] = fileChanges.count();
                commitInfo["isMessageOnly"] = (fileChanges.count() == 0);
                
                history.append(commitInfo);
            }
        }
        
        return history;
    });
    
    QFutureWatcher<QVariantList> *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this, [this, watcher]() {
        m_commitHistory = watcher->result();
        emit commitHistoryChanged();
        setLoading(false);
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

void GitManager::amendCommitMessage(const QString &newMessage)
{
    if (newMessage.trimmed().isEmpty()) {
        setError("提交信息不能为空");
        return;
    }

    setLoading(true);
    
    // Amend the last commit message (local, fast)
    QProcess process;
    process.setWorkingDirectory(m_repoPath);
    process.start("git", QStringList() << "commit" << "--amend" << "--allow-empty" << "-m" << newMessage.trimmed());
    process.waitForFinished(30000);
    
    int exitCode = process.exitCode();
    QString stdErr = QString::fromUtf8(process.readAllStandardError());
    
    if (exitCode != 0) {
        setLoading(false);
        setError("修改提交信息失败: " + stdErr);
        return;
    }

    // Force push to update remote - async
    runAsyncGitCommand({"push", "--force", "origin", m_currentBranch}, 
                       "提交信息已修改并推送",
                       "提交信息已修改，但推送失败");
}

void GitManager::revertCommit(const QString &commitHash, const QString &message)
{
    if (commitHash.isEmpty()) return;

    setLoading(true);
    
    // Revert the specific commit
    QString commitMsg = message.isEmpty() ? "Revert commit " + commitHash.left(7) : message;
    QString result = runGitCommand({"revert", "--no-edit", commitHash});
    
    if (result.isEmpty()) {
        // Try with message
        runGitCommand({"revert", "--no-commit", commitHash});
        runGitCommand({"commit", "-m", commitMsg});
    }

    // Push to remote
    runGitCommand({"push", "origin", m_currentBranch});
    
    setLoading(false);
    emit operationSuccess("已撤销提交并推送");
    loadCommitHistory();
    refresh();
}

void GitManager::configureUser(const QString &name, const QString &email, bool global)
{
    if (name.trimmed().isEmpty() || email.trimmed().isEmpty()) {
        setError("用户名和邮箱不能为空");
        return;
    }

    setLoading(true);
    
    QProcess process;
    if (global) {
        // Global config
        process.start("git", {"config", "--global", "user.name", name});
        process.waitForFinished(10000);
        
        process.start("git", {"config", "--global", "user.email", email});
        process.waitForFinished(10000);
    } else {
        // Local repo config
        process.setWorkingDirectory(m_repoPath);
        process.start("git", {"config", "user.name", name});
        process.waitForFinished(10000);
        
        process.start("git", {"config", "user.email", email});
        process.waitForFinished(10000);
    }
    
    // Update cached user info
    m_userName = name;
    m_userEmail = email;
    emit userInfoChanged();
    
    setLoading(false);
    emit operationSuccess(global ? "全局用户配置已保存" : "仓库用户配置已保存");
}

void GitManager::runGitInstaller()
{
    // Try multiple possible paths for the installer
    QStringList possiblePaths;
    
    // 1. Next to the executable
    QString appDir = QCoreApplication::applicationDirPath();
    possiblePaths << appDir + "/Gitsetup/Git-2.52.0-64-bit.exe";
    
    // 2. In parent directory (for build folder structure)
    possiblePaths << appDir + "/../Gitsetup/Git-2.52.0-64-bit.exe";
    possiblePaths << appDir + "/../../Gitsetup/Git-2.52.0-64-bit.exe";
    possiblePaths << appDir + "/../../../Gitsetup/Git-2.52.0-64-bit.exe";
    possiblePaths << appDir + "/../../../../Gitsetup/Git-2.52.0-64-bit.exe";
    
    // 3. Source directory (hardcoded for development)
    possiblePaths << "D:/XiangMu/C++/Git/Gitsetup/Git-2.52.0-64-bit.exe";
    
    QString installerPath;
    for (const QString &path : possiblePaths) {
        QFileInfo fileInfo(path);
        if (fileInfo.exists()) {
            installerPath = fileInfo.absoluteFilePath();
            break;
        }
    }
    
    if (installerPath.isEmpty()) {
        setError("找不到 Git 安装程序，请确保 Gitsetup 文件夹存在");
        return;
    }
    
    // Run the installer
    bool success = QProcess::startDetached(installerPath, QStringList());
    
    if (success) {
        emit operationSuccess("Git 安装程序已启动");
    } else {
        setError("无法启动 Git 安装程序");
    }
}

QStringList GitManager::recentRepos() const
{
    QSettings settings("GitPushTool", "RecentRepos");
    return settings.value("recentRepos").toStringList();
}

void GitManager::addRecentRepo(const QString &path)
{
    if (path.isEmpty()) return;
    
    QSettings settings("GitPushTool", "RecentRepos");
    QStringList repos = settings.value("recentRepos").toStringList();
    
    // Remove if already exists (to move to front)
    repos.removeAll(path);
    
    // Add to front
    repos.prepend(path);
    
    // Keep only last 10
    while (repos.size() > 10) {
        repos.removeLast();
    }
    
    settings.setValue("recentRepos", repos);
    emit recentReposChanged();
}

void GitManager::removeRecentRepo(const QString &path)
{
    QSettings settings("GitPushTool", "RecentRepos");
    QStringList repos = settings.value("recentRepos").toStringList();
    repos.removeAll(path);
    settings.setValue("recentRepos", repos);
    emit recentReposChanged();
}

void GitManager::clearRecentRepos()
{
    QSettings settings("GitPushTool", "RecentRepos");
    settings.setValue("recentRepos", QStringList());
    emit recentReposChanged();
}

void GitManager::loadGlobalUserInfo()
{
    // Read global git config (doesn't need a repo)
    QProcess process;
    process.start("git", {"config", "--global", "user.name"});
    process.waitForFinished(5000);
    QString name = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    
    process.start("git", {"config", "--global", "user.email"});
    process.waitForFinished(5000);
    QString email = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    
    if (!name.isEmpty() || !email.isEmpty()) {
        m_userName = name;
        m_userEmail = email;
        emit userInfoChanged();
    }
}

void GitManager::runAsyncGitCommand(const QStringList &args, const QString &successMsg, const QString &errorPrefix)
{
    if (m_repoPath.isEmpty()) {
        setLoading(false);
        setError("未选择仓库");
        return;
    }
    
    // If async process is already running, wait for it
    if (m_asyncProcess->state() != QProcess::NotRunning) {
        setLoading(false);
        setError("有操作正在进行中，请稍候");
        return;
    }
    
    m_asyncSuccessMsg = successMsg;
    m_asyncErrorPrefix = errorPrefix;
    
    m_asyncProcess->setWorkingDirectory(m_repoPath);
    m_asyncProcess->start("git", args);
}

QVariantList GitManager::largeFilesList() const
{
    return m_largeFilesList;
}

void GitManager::findLargeFiles(int minSizeMB)
{
    if (m_repoPath.isEmpty()) return;
    
    setLoading(true);
    m_largeFilesList.clear();
    emit largeFilesChanged();
    
    QString repoPath = m_repoPath;
    qint64 minSize = minSizeMB * 1024 * 1024;
    
    // Run in background thread
    QFuture<QVariantList> future = QtConcurrent::run([repoPath, minSize]() -> QVariantList {
        QVariantList result;
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        // Step 1: Get all objects with their paths using rev-list
        process.start("git", {"rev-list", "--objects", "--all"});
        process.waitForFinished(60000);
        QString objects = QString::fromUtf8(process.readAllStandardOutput());
        
        QMap<QString, QString> hashToPath;
        QStringList objLines = objects.split('\n', Qt::SkipEmptyParts);
        for (const QString &line : objLines) {
            int spaceIdx = line.indexOf(' ');
            if (spaceIdx > 0) {
                QString hash = line.left(spaceIdx);
                QString path = line.mid(spaceIdx + 1);
                if (!path.isEmpty()) {
                    hashToPath[hash] = path;
                }
            }
        }
        
        // Step 2: Get sizes for ALL objects (both packed and loose) using cat-file --batch-check
        // This is the most reliable method
        QMap<QString, qint64> objectSizes;
        
        // Batch check all blob objects for their sizes
        process.start("git", {"cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)", "--batch-all-objects"});
        process.waitForFinished(120000);
        QString batchOutput = QString::fromUtf8(process.readAllStandardOutput());
        
        QStringList batchLines = batchOutput.split('\n', Qt::SkipEmptyParts);
        for (const QString &line : batchLines) {
            QStringList parts = line.split(' ', Qt::SkipEmptyParts);
            if (parts.size() >= 3 && parts[1] == "blob") {
                QString hash = parts[0];
                qint64 size = parts[2].toLongLong();
                if (size >= minSize) {
                    objectSizes[hash] = size;
                }
            }
        }
        
        // Step 3: Build result list - only include objects that have a file path
        for (auto it = objectSizes.begin(); it != objectSizes.end(); ++it) {
            QString hash = it.key();
            qint64 size = it.value();
            QString path = hashToPath.value(hash, "");
            
            // Only include if we have a valid file path
            if (!path.isEmpty()) {
                QVariantMap fileInfo;
                fileInfo["hash"] = hash;
                fileInfo["path"] = path;
                fileInfo["size"] = size;
                fileInfo["sizeStr"] = QString::number(size / 1024.0 / 1024.0, 'f', 2) + " MB";
                result.append(fileInfo);
            }
        }
        
        // Sort by size descending
        std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap()["size"].toLongLong() > b.toMap()["size"].toLongLong();
        });
        
        return result;
    });
    
    // Watch for completion
    QFutureWatcher<QVariantList> *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this, [this, watcher]() {
        m_largeFilesList = watcher->result();
        setLoading(false);
        emit largeFilesChanged();
        watcher->deleteLater();
    });
    
    watcher->setFuture(future);
}

void GitManager::removeLargeFileFromHistory(const QString &filePath)
{
    if (m_repoPath.isEmpty() || filePath.isEmpty()) return;
    
    setLoading(true);
    
    // Run in a separate thread using QtConcurrent
    QString repoPath = m_repoPath;
    
    QFuture<bool> future = QtConcurrent::run([repoPath, filePath]() -> bool {
        QProcess process;
        process.setWorkingDirectory(repoPath);
        
        // Use git filter-branch to remove file from history
        QString filterCmd = QString("git rm --cached --ignore-unmatch \"%1\"").arg(filePath);
        
        process.start("git", {"filter-branch", "--force", "--index-filter", 
                              filterCmd, "--prune-empty", "--tag-name-filter", "cat", "--", "--all"});
        process.waitForFinished(300000); // 5 minutes timeout
        
        int exitCode = process.exitCode();
        QString errorOutput = QString::fromUtf8(process.readAllStandardError());
        
        if (exitCode != 0 && !errorOutput.contains("Ref 'refs/heads")) {
            return false;
        }
        
        // Clean up refs
        process.start("git", {"for-each-ref", "--format=%(refname)", "refs/original/"});
        process.waitForFinished(10000);
        QString refs = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        
        if (!refs.isEmpty()) {
            QStringList refList = refs.split('\n', Qt::SkipEmptyParts);
            for (const QString &ref : refList) {
                process.start("git", {"update-ref", "-d", ref});
                process.waitForFinished(5000);
            }
        }
        
        // Expire reflog
        process.start("git", {"reflog", "expire", "--expire=now", "--all"});
        process.waitForFinished(30000);
        
        // Garbage collect
        process.start("git", {"gc", "--prune=now", "--aggressive"});
        process.waitForFinished(120000);
        
        return true;
    });
    
    // Watch for completion
    QFutureWatcher<bool> *watcher = new QFutureWatcher<bool>(this);
    connect(watcher, &QFutureWatcher<bool>::finished, this, [this, watcher, filePath]() {
        bool success = watcher->result();
        setLoading(false);
        
        if (success) {
            emit operationSuccess("已从历史中清理: " + filePath + "\n请点击强制推送更新远程仓库");
        } else {
            setError("清理失败，请检查文件路径");
        }
        
        refresh();
        watcher->deleteLater();
    });
    
    watcher->setFuture(future);
}

void GitManager::forcePush()
{
    if (m_repoPath.isEmpty()) return;
    
    setLoading(true);
    runAsyncGitCommand({"push", "--force", "origin", m_currentBranch}, "强制推送成功", "强制推送失败");
}
void GitManager::setBulkOperationMode(bool enabled)
{
    if (m_bulkOperationMode != enabled) {
        m_bulkOperationMode = enabled;
        qDebug() << "Bulk operation mode:" << (enabled ? "enabled" : "disabled");
        
        if (!enabled) {
            // Re-enable file watching after bulk operation
            QTimer::singleShot(2000, this, [this]() {
                if (!m_repoPath.isEmpty()) {
                    setupFileWatcherAsync();
                    refresh();
                }
            });
        }
    }
}
QString GitManager::formatFileSize(qint64 size)
{
    if (size < 1024) {
        return QString::number(size) + " B";
    } else if (size < 1024 * 1024) {
        return QString::number(size / 1024.0, 'f', 1) + " KB";
    } else if (size < 1024 * 1024 * 1024) {
        return QString::number(size / (1024.0 * 1024.0), 'f', 1) + " MB";
    } else {
        return QString::number(size / (1024.0 * 1024.0 * 1024.0), 'f', 1) + " GB";
    }
}