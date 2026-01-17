#ifndef GITMANAGER_H
#define GITMANAGER_H

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QFileSystemWatcher>
#include <QTimer>
#include <qqml.h>

class GitManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString repoPath READ repoPath WRITE setRepoPath NOTIFY repoPathChanged)
    Q_PROPERTY(QString currentBranch READ currentBranch NOTIFY currentBranchChanged)
    Q_PROPERTY(QStringList branches READ branches NOTIFY branchesChanged)
    Q_PROPERTY(QStringList localBranches READ localBranches NOTIFY branchesChanged)
    Q_PROPERTY(QStringList remoteBranches READ remoteBranches NOTIFY branchesChanged)
    Q_PROPERTY(QVariantList changedFiles READ changedFiles NOTIFY changedFilesChanged)
    Q_PROPERTY(QVariantList stagedFiles READ stagedFiles NOTIFY stagedFilesChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool isValidRepo READ isValidRepo NOTIFY isValidRepoChanged)
    Q_PROPERTY(QVariantList repoFiles READ repoFiles NOTIFY repoFilesChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString fileContent READ fileContent NOTIFY fileContentChanged)
    Q_PROPERTY(QVariantList remoteFiles READ remoteFiles NOTIFY remoteFilesChanged)
    Q_PROPERTY(QString remoteCurrentPath READ remoteCurrentPath NOTIFY remoteCurrentPathChanged)
    Q_PROPERTY(QString remoteUrl READ remoteUrl NOTIFY remoteUrlChanged)
    Q_PROPERTY(QVariantList commitHistory READ commitHistory NOTIFY commitHistoryChanged)
    Q_PROPERTY(QVariantMap lastCommit READ lastCommit NOTIFY commitHistoryChanged)
    Q_PROPERTY(QStringList lastCommitFiles READ lastCommitFiles NOTIFY commitHistoryChanged)
    Q_PROPERTY(QString lastCommitTime READ lastCommitTime NOTIFY lastCommitTimeChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY userInfoChanged)
    Q_PROPERTY(QString userEmail READ userEmail NOTIFY userInfoChanged)
    Q_PROPERTY(QString userAvatar READ userAvatar NOTIFY userInfoChanged)
    Q_PROPERTY(QStringList recentReposList READ recentRepos NOTIFY recentReposChanged)
    Q_PROPERTY(QVariantList largeFilesList READ largeFilesList NOTIFY largeFilesChanged)

public:
    explicit GitManager(QObject *parent = nullptr);

    QString repoPath() const;
    void setRepoPath(const QString &path);

    QString currentBranch() const;
    QStringList branches() const;
    QStringList localBranches() const;
    QStringList remoteBranches() const;
    QVariantList changedFiles() const;
    QVariantList stagedFiles() const;
    bool isLoading() const;
    QString lastError() const;
    bool isValidRepo() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void stageFile(const QString &filePath);
    Q_INVOKABLE void stageFiles(const QStringList &filePaths);
    Q_INVOKABLE void unstageFile(const QString &filePath);
    Q_INVOKABLE void unstageFiles(const QStringList &filePaths);
    Q_INVOKABLE void stageAll();
    Q_INVOKABLE void unstageAll();
    Q_INVOKABLE void commit(const QString &message);
    Q_INVOKABLE void quickSync(const QString &message);
    Q_INVOKABLE void push();
    Q_INVOKABLE void pull();
    Q_INVOKABLE void switchBranch(const QString &branchName);
    Q_INVOKABLE void createBranch(const QString &branchName);
    Q_INVOKABLE void deleteBranch(const QString &branchName);
    Q_INVOKABLE void mergeBranch(const QString &branchName);
    Q_INVOKABLE void discardChanges(const QString &filePath);
    Q_INVOKABLE void discardAllChanges();
    Q_INVOKABLE void deleteNewFile(const QString &filePath);
    Q_INVOKABLE void addToGitignore(const QString &pattern);
    Q_INVOKABLE QStringList getGitignoreRules();
    Q_INVOKABLE void removeFromGitignore(const QString &pattern);
    Q_INVOKABLE void abortMerge();
    Q_INVOKABLE void resetToBranch(const QString &branchName);
    Q_INVOKABLE void cloneRepo(const QString &url, const QString &targetPath);
    Q_INVOKABLE void loadRepoFiles(const QString &subPath = "");
    Q_INVOKABLE void openFile(const QString &filePath);
    Q_INVOKABLE void openFileLocation(const QString &filePath);
    Q_INVOKABLE QVariantList getFileDiff(const QString &filePath, bool staged = false);
    Q_INVOKABLE void saveFile(const QString &filePath, const QString &content);
    Q_INVOKABLE void deleteRepoFile(const QString &filePath);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void loadRemoteFiles(const QString &subPath = "");
    Q_INVOKABLE void goBackRemote();
    Q_INVOKABLE void deleteRemoteFile(const QString &filePath, const QString &message);
    Q_INVOKABLE void saveAndPushFile(const QString &filePath, const QString &content, const QString &message);
    Q_INVOKABLE void renameRemoteFile(const QString &oldPath, const QString &newPath, const QString &message);
    Q_INVOKABLE void loadCommitHistory();
    Q_INVOKABLE void amendCommitMessage(const QString &newMessage);
    Q_INVOKABLE void revertCommit(const QString &commitHash, const QString &message);
    Q_INVOKABLE void configureUser(const QString &name, const QString &email, bool global);
    Q_INVOKABLE void runGitInstaller();
    Q_INVOKABLE QStringList recentRepos() const;
    Q_INVOKABLE void addRecentRepo(const QString &path);
    Q_INVOKABLE void removeRecentRepo(const QString &path);
    Q_INVOKABLE void clearRecentRepos();
    Q_INVOKABLE void findLargeFiles(int minSizeMB = 50);
    Q_INVOKABLE void removeLargeFileFromHistory(const QString &filePath);
    Q_INVOKABLE void forcePush();
    Q_INVOKABLE void setBulkOperationMode(bool enabled);
    Q_INVOKABLE void initAndPushRepo(const QString &remoteUrl, const QString &branchName);
    Q_INVOKABLE void pushWithUnrelatedHistories();
    Q_INVOKABLE void unlockRepository();
    
    QVariantList largeFilesList() const;

    QVariantList repoFiles() const;
    QString currentPath() const;
    QString fileContent() const;
    QVariantList remoteFiles() const;
    QString remoteCurrentPath() const;
    QString remoteUrl() const;
    QVariantList commitHistory() const;
    QVariantMap lastCommit() const;
    QStringList lastCommitFiles() const;
    QString lastCommitTime() const;
    QString userName() const;
    QString userEmail() const;
    QString userAvatar() const;

signals:
    void repoPathChanged();
    void currentBranchChanged();
    void branchesChanged();
    void changedFilesChanged();
    void stagedFilesChanged();
    void isLoadingChanged();
    void lastErrorChanged();
    void isValidRepoChanged();
    void repoFilesChanged();
    void currentPathChanged();
    void fileContentChanged();
    void remoteFilesChanged();
    void remoteCurrentPathChanged();
    void remoteUrlChanged();
    void commitHistoryChanged();
    void userInfoChanged();
    void operationSuccess(const QString &message);
    void operationFailed(const QString &message);
    void recentReposChanged();
    void largeFilesChanged();
    void remoteFilesNeedRefresh();
    void lastCommitTimeChanged();

private:
    QString runGitCommand(const QStringList &args);
    void parseStatus();
    void parseStatusAsync(bool showLoading = true);
    void updateBranches();
    void setLoading(bool loading);
    void setError(const QString &error);
    QString translateGitError(const QString &error);
    void setupFileWatcher();
    void setupFileWatcherAsync();
    void watchDirectory(const QString &path, int depth = 0);
    void watchDirectoryRecursively(const QString &path, int depth = 0);
    void cleanupFileWatcherAsync();
    static QString decodeOctalEscapes(const QString &input);
    static QString formatFileSize(qint64 size);
    void loadGlobalUserInfo();
    void runAsyncGitCommand(const QStringList &args, const QString &successMsg, const QString &errorPrefix);

    QString m_repoPath;
    QString m_currentBranch;
    QStringList m_branches;
    QStringList m_localBranches;
    QStringList m_remoteBranches;
    QVariantList m_changedFiles;
    QVariantList m_stagedFiles;
    QVariantList m_repoFiles;
    QString m_currentPath;
    QString m_fileContent;
    QVariantList m_remoteFiles;
    QString m_remoteCurrentPath;
    QString m_remoteUrl;
    QVariantList m_commitHistory;
    QString m_userName;
    QString m_userEmail;
    bool m_isLoading = false;
    QString m_lastError;
    bool m_bulkOperationMode = false;
    bool m_isValidRepo = false;
    
    // File system watcher for auto-refresh
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_refreshTimer = nullptr;
    bool m_pendingRefresh = false;
    
    // Async process for long operations
    QProcess *m_asyncProcess = nullptr;
    QString m_asyncSuccessMsg;
    QString m_asyncErrorPrefix;
    QString m_cloneTargetPath;  // For clone operation
    
    // Large files list
    QVariantList m_largeFilesList;
    
    // File watcher setup flag to prevent infinite loops
    bool m_settingUpWatcher = false;
};

#endif // GITMANAGER_H
