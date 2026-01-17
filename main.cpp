#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QAction>
#include <QSettings>
#include <QSharedMemory>
#include <QMessageBox>
#include <QQuickWindow>
#include <QDir>
#include <QFile>
#include <QStyle>
#include "gitmanager.h"

class TrayManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool minimizeToTray READ minimizeToTray WRITE setMinimizeToTray NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(bool rememberChoice READ rememberChoice WRITE setRememberChoice NOTIFY rememberChoiceChanged)
    // Settings properties
    Q_PROPERTY(bool isDarkMode READ isDarkMode WRITE setIsDarkMode NOTIFY isDarkModeChanged)
    Q_PROPERTY(QString commitTemplate READ commitTemplate WRITE setCommitTemplate NOTIFY commitTemplateChanged)
    Q_PROPERTY(bool autoPush READ autoPush WRITE setAutoPush NOTIFY autoPushChanged)
    Q_PROPERTY(bool autoStart READ autoStart WRITE setAutoStart NOTIFY autoStartChanged)
    Q_PROPERTY(QString shortcutCommit READ shortcutCommit WRITE setShortcutCommit NOTIFY shortcutCommitChanged)
    Q_PROPERTY(QString shortcutCommitOnly READ shortcutCommitOnly WRITE setShortcutCommitOnly NOTIFY shortcutCommitOnlyChanged)
    Q_PROPERTY(QString shortcutRefresh READ shortcutRefresh WRITE setShortcutRefresh NOTIFY shortcutRefreshChanged)
    Q_PROPERTY(QString shortcutPush READ shortcutPush WRITE setShortcutPush NOTIFY shortcutPushChanged)
    Q_PROPERTY(QString shortcutPull READ shortcutPull WRITE setShortcutPull NOTIFY shortcutPullChanged)
    Q_PROPERTY(int windowX READ windowX WRITE setWindowX NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowY READ windowY WRITE setWindowY NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowWidth READ windowWidth WRITE setWindowWidth NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowHeight READ windowHeight WRITE setWindowHeight NOTIFY windowGeometryChanged)

public:
    explicit TrayManager(QObject *parent = nullptr) : QObject(parent) {
        m_settings = new QSettings("GitTool", "GitPushTool", this);
        m_minimizeToTray = m_settings->value("minimizeToTray", false).toBool();
        m_rememberChoice = m_settings->value("rememberChoice", false).toBool();
        // Load settings
        m_isDarkMode = m_settings->value("isDarkMode", false).toBool();
        m_commitTemplate = m_settings->value("commitTemplate", "").toString();
        m_autoPush = m_settings->value("autoPush", true).toBool();
        m_autoStart = checkAutoStart();
        m_shortcutCommit = m_settings->value("shortcutCommit", "Ctrl+Return").toString();
        m_shortcutCommitOnly = m_settings->value("shortcutCommitOnly", "Ctrl+Shift+Return").toString();
        m_shortcutRefresh = m_settings->value("shortcutRefresh", "Ctrl+R").toString();
        m_shortcutPush = m_settings->value("shortcutPush", "Ctrl+Shift+P").toString();
        m_shortcutPull = m_settings->value("shortcutPull", "Ctrl+Shift+L").toString();
        m_windowX = m_settings->value("windowX", -1).toInt();
        m_windowY = m_settings->value("windowY", -1).toInt();
        m_windowWidth = m_settings->value("windowWidth", 1000).toInt();
        m_windowHeight = m_settings->value("windowHeight", 680).toInt();
    }

    bool minimizeToTray() const { return m_minimizeToTray; }
    void setMinimizeToTray(bool value) {
        if (m_minimizeToTray != value) {
            m_minimizeToTray = value;
            if (m_rememberChoice) {
                m_settings->setValue("minimizeToTray", value);
            }
            emit minimizeToTrayChanged();
        }
    }

    bool rememberChoice() const { return m_rememberChoice; }
    void setRememberChoice(bool value) {
        if (m_rememberChoice != value) {
            m_rememberChoice = value;
            m_settings->setValue("rememberChoice", value);
            if (value) {
                m_settings->setValue("minimizeToTray", m_minimizeToTray);
            }
            emit rememberChoiceChanged();
        }
    }

    Q_INVOKABLE bool hasRememberedChoice() const {
        return m_settings->value("rememberChoice", false).toBool();
    }

    Q_INVOKABLE void resetCloseChoice() {
        m_settings->setValue("rememberChoice", false);
        m_rememberChoice = false;
        emit rememberChoiceChanged();
    }

    Q_INVOKABLE void showWindow() {
        emit requestShowWindow();
    }

    Q_INVOKABLE void quitApp() {
        emit requestQuit();
    }

    // Settings getters/setters
    bool isDarkMode() const { return m_isDarkMode; }
    void setIsDarkMode(bool value) {
        if (m_isDarkMode != value) {
            m_isDarkMode = value;
            m_settings->setValue("isDarkMode", value);
            emit isDarkModeChanged();
        }
    }

    QString commitTemplate() const { return m_commitTemplate; }
    void setCommitTemplate(const QString &value) {
        if (m_commitTemplate != value) {
            m_commitTemplate = value;
            m_settings->setValue("commitTemplate", value);
            emit commitTemplateChanged();
        }
    }

    bool autoPush() const { return m_autoPush; }
    void setAutoPush(bool value) {
        if (m_autoPush != value) {
            m_autoPush = value;
            m_settings->setValue("autoPush", value);
            emit autoPushChanged();
        }
    }

    bool autoStart() const { return m_autoStart; }
    void setAutoStart(bool value) {
        if (m_autoStart != value) {
            m_autoStart = value;
            setAutoStartRegistry(value);
            emit autoStartChanged();
        }
    }

    QString shortcutCommit() const { return m_shortcutCommit; }
    void setShortcutCommit(const QString &value) {
        if (m_shortcutCommit != value) {
            m_shortcutCommit = value;
            m_settings->setValue("shortcutCommit", value);
            emit shortcutCommitChanged();
        }
    }

    QString shortcutCommitOnly() const { return m_shortcutCommitOnly; }
    void setShortcutCommitOnly(const QString &value) {
        if (m_shortcutCommitOnly != value) {
            m_shortcutCommitOnly = value;
            m_settings->setValue("shortcutCommitOnly", value);
            emit shortcutCommitOnlyChanged();
        }
    }

    QString shortcutRefresh() const { return m_shortcutRefresh; }
    void setShortcutRefresh(const QString &value) {
        if (m_shortcutRefresh != value) {
            m_shortcutRefresh = value;
            m_settings->setValue("shortcutRefresh", value);
            emit shortcutRefreshChanged();
        }
    }

    QString shortcutPush() const { return m_shortcutPush; }
    void setShortcutPush(const QString &value) {
        if (m_shortcutPush != value) {
            m_shortcutPush = value;
            m_settings->setValue("shortcutPush", value);
            emit shortcutPushChanged();
        }
    }

    QString shortcutPull() const { return m_shortcutPull; }
    void setShortcutPull(const QString &value) {
        if (m_shortcutPull != value) {
            m_shortcutPull = value;
            m_settings->setValue("shortcutPull", value);
            emit shortcutPullChanged();
        }
    }

    int windowX() const { return m_windowX; }
    void setWindowX(int value) {
        if (m_windowX != value) {
            m_windowX = value;
            m_settings->setValue("windowX", value);
            emit windowGeometryChanged();
        }
    }

    int windowY() const { return m_windowY; }
    void setWindowY(int value) {
        if (m_windowY != value) {
            m_windowY = value;
            m_settings->setValue("windowY", value);
            emit windowGeometryChanged();
        }
    }

    int windowWidth() const { return m_windowWidth; }
    void setWindowWidth(int value) {
        if (m_windowWidth != value) {
            m_windowWidth = value;
            m_settings->setValue("windowWidth", value);
            emit windowGeometryChanged();
        }
    }

    int windowHeight() const { return m_windowHeight; }
    void setWindowHeight(int value) {
        if (m_windowHeight != value) {
            m_windowHeight = value;
            m_settings->setValue("windowHeight", value);
            emit windowGeometryChanged();
        }
    }

    Q_INVOKABLE void saveWindowGeometry(int x, int y, int w, int h) {
        setWindowX(x);
        setWindowY(y);
        setWindowWidth(w);
        setWindowHeight(h);
    }

signals:
    void minimizeToTrayChanged();
    void rememberChoiceChanged();
    void requestShowWindow();
    void requestQuit();
    void isDarkModeChanged();
    void commitTemplateChanged();
    void autoPushChanged();
    void autoStartChanged();
    void shortcutCommitChanged();
    void shortcutCommitOnlyChanged();
    void shortcutRefreshChanged();
    void shortcutPushChanged();
    void shortcutPullChanged();
    void windowGeometryChanged();

private:
    // Check if auto start is enabled in registry
    bool checkAutoStart() {
        QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", QSettings::NativeFormat);
        QString path = reg.value("GitPushTool", "").toString();
        return !path.isEmpty();
    }

    // Set auto start in registry
    void setAutoStartRegistry(bool enable) {
        QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", QSettings::NativeFormat);
        if (enable) {
            QString appPath = QCoreApplication::applicationFilePath();
            appPath = appPath.replace("/", "\\");
            reg.setValue("GitPushTool", "\"" + appPath + "\"");
        } else {
            reg.remove("GitPushTool");
        }
    }

    QSettings *m_settings;
    bool m_minimizeToTray = false;
    bool m_rememberChoice = false;
    bool m_isDarkMode = false;
    QString m_commitTemplate;
    bool m_autoPush = true;
    bool m_autoStart = false;
    QString m_shortcutCommit;
    QString m_shortcutCommitOnly;
    QString m_shortcutRefresh;
    QString m_shortcutPush;
    QString m_shortcutPull;
    int m_windowX = -1;
    int m_windowY = -1;
    int m_windowWidth = 1000;
    int m_windowHeight = 680;
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName("Git Push Tool");
    app.setOrganizationName("GitTool");
    
    // Try to load icon from various paths
    QString appDir = QCoreApplication::applicationDirPath();
    QString sourceDir = QString(__FILE__).section('/', 0, -2); // Source directory
    QIcon appIcon;
    
    // Try source directory (for development)
    QString iconPath = sourceDir + "/images/icon.ico";
    if (QFile::exists(iconPath)) {
        appIcon = QIcon(iconPath);
    }
    
    // Try exe directory
    if (appIcon.isNull()) {
        iconPath = appDir + "/images/icon.ico";
        if (QFile::exists(iconPath)) {
            appIcon = QIcon(iconPath);
        }
    }
    
    if (appIcon.isNull()) {
        iconPath = appDir + "/icon.ico";
        if (QFile::exists(iconPath)) {
            appIcon = QIcon(iconPath);
        }
    }
    
    // Try qrc paths
    if (appIcon.isNull()) {
        appIcon = QIcon(":/images/icon.ico");
    }
    if (appIcon.isNull()) {
        appIcon = QIcon(":/Git/images/icon.ico");
    }
    
    // Use a built-in icon as fallback
    if (appIcon.isNull()) {
        appIcon = QApplication::style()->standardIcon(QStyle::SP_ComputerIcon);
    }
    
    app.setWindowIcon(appIcon);
    
    // Single instance check
    QSharedMemory sharedMemory("GitPushToolSingleInstance");
    if (!sharedMemory.create(1)) {
        QMessageBox::warning(nullptr, "提示", "软件已经打开，无需重复打开！");
        return 0;
    }

    // Create tray manager
    TrayManager trayManager;

    QQmlApplicationEngine engine;
    
    // Expose tray manager to QML
    engine.rootContext()->setContextProperty("trayManager", &trayManager);
    
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    
    engine.loadFromModule("Git", "Main");

    // Get the main window
    QQuickWindow *window = nullptr;
    if (!engine.rootObjects().isEmpty()) {
        window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
    }

    // Setup system tray
    QSystemTrayIcon *trayIcon = new QSystemTrayIcon(&app);
    trayIcon->setIcon(appIcon);
    trayIcon->setToolTip("Git 推送工具");

    // Tray menu
    QMenu *trayMenu = new QMenu();
    QAction *showAction = trayMenu->addAction("显示主窗口");
    QAction *resetAction = trayMenu->addAction("重置关闭选项");
    trayMenu->addSeparator();
    QAction *quitAction = trayMenu->addAction("退出");
    
    trayIcon->setContextMenu(trayMenu);
    trayIcon->show();

    // Connect tray actions
    QObject::connect(showAction, &QAction::triggered, [window]() {
        if (window) {
            window->show();
            window->raise();
            window->requestActivate();
        }
    });

    QObject::connect(resetAction, &QAction::triggered, [&trayManager]() {
        trayManager.resetCloseChoice();
    });

    QObject::connect(quitAction, &QAction::triggered, &app, &QApplication::quit);

    // Double click tray icon to show window
    QObject::connect(trayIcon, &QSystemTrayIcon::activated, [window](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::DoubleClick || reason == QSystemTrayIcon::Trigger) {
            if (window) {
                window->show();
                window->raise();
                window->requestActivate();
            }
        }
    });

    // Connect tray manager signals
    QObject::connect(&trayManager, &TrayManager::requestShowWindow, [window]() {
        if (window) {
            window->show();
            window->raise();
            window->requestActivate();
        }
    });

    QObject::connect(&trayManager, &TrayManager::requestQuit, &app, &QApplication::quit);

    return app.exec();
}

#include "main.moc"
