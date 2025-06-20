/*
 * Copyright (C) 2011-2024 MicroSIP (http://www.microsip.org)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#pragma once

#include "stdafx.h"

#include <afxwin.h>

#include "define.h"
#include "json.h"
#include "addons.h"
#include <pjsua-lib/pjsua.h>
#include <pjsua-lib/pjsua_internal.h>

#include "MMNotificationClient.h"

#include "BaseDialog.h"
#include "RinginDlg.h"
#include "AccountDlg.h"
#include "SettingsDlg.h"
#include "ShortcutsDlg.h"
#include "MessagesDlg.h"

#include "Dialer.h"
#include "Contacts.h"
#include "Calls.h"
#include "Preview.h"
#include "Transfer.h"
#include "StatusBar.h"

// CmainDlg dialog
class CmainDlg : public CBaseDialog
{
	// Construction
public:
	CmainDlg(CWnd* pParent = NULL);	// standard constructor
	~CmainDlg();

	// Dialog Data
	enum { IDD = IDD_MAIN };

	bool m_startMinimized;
	CButton m_ButtonMenu;
	SettingsDlg* settingsDlg;
	bool shortcutsEnabled;
	bool shortcutsBottom;
	ShortcutsDlg* shortcutsDlg;
	MessagesDlg* messagesDlg;
	Transfer* transferDlg;
	AccountDlg* accountDlg;

	Dialer* pageDialer;
	Contacts* pageContacts;
	bool usersDirectoryLoaded;
	bool shortcutsURLLoaded;
	Calls* pageCalls;

	BOOL notStopRinging;
	CArray <RinginDlg*> ringinDlgs;
	CString dialNumberDelayed;
	pjsua_call_id autoAnswerTimerCallId;
	pjsua_call_id autoAnswerPlayCallId;
	pjsua_call_id forwardingTimerCallId;
	pjsua_acc_config acc_cfg;

	player_eof_data *player_eof_data;

	int iconStatusbar;
	CImageList* imageListStatus;
	int widthAdd;
	int heightAdd;
	bool missed;

	CString callIdIncomingIgnore;
	CList<int,int> toneCalls;
	CList<int,int> attendedCalls;
	CList<CString> audioCodecList;
	CList<int> confernceCalls;
	
	void InitUI();
	void ShowTrayIcon();
	void OnCreated();
	void PJCreate();
	void PJCreateRaw();
	void PJDestroy(bool exit = false);
	void PJAccountAdd();
	void PJAccountAddRaw();
	void PJAccountAddLocal();
	void PJAccountDelete(bool deep = false, bool exit = false, CStringA code = "");
	void PJAccountDeleteLocal();
	void PJAccountConfig(pjsua_acc_config *acc_cfg, Account *account);
	void PJAudioCodecs();
#ifdef _GLOBAL_VIDEO
	void PJVideoCodecs();
#endif

	bool CommandLine(CString params);
	void TabFocusSet() override;
	void UpdateWindowText(CString = CString(), int icon = IDI_DEFAULT, bool afterRegister = false);
	void PublishStatus(bool online = true, bool init=false);
	void TrayIconUpdateTip();
	void BaloonPopup(CString title, CString message, DWORD flags = NIIF_WARNING); // CORRIGIDO: Adicionado 'void' como tipo de retorno.
	void SwitchDND(int state = -1, bool update = false);
	bool GotoTabLParam(LPARAM lParam);
	bool GotoTab(int i, CTabCtrl* tab = NULL) override;
	void ProcessCommand(CString str) override;
	void DialNumberFromCommandLine(CString params);
	void DialNumber(CString params);
	bool MakeCall(CString number, bool hasVideo = false, bool fromCommandLine = false, bool noTransform = false);
	bool MessagesOpen(CString number, bool forCall = false, bool noTransform = false);
	bool AutoAnswer(pjsua_call_id call_id, bool force = false);
	pjsua_call_id CurrentCallId();
	void ShortcutAction(Shortcut *shortcut, bool block = false, bool second = false);
	void ShortcutsRemoveAll();
	bool isSubscribed;
	void SubsribeNumber(CString *number);
	void UnsubscribeNumber(CString* number);
	void Subscribe();
	void Unsubscribe();
	void PlayerPlay(CString filename, bool noLoop = false, bool inCall = false, bool isAA = false);
	BOOL CopyStringToClipboard( IN const CString & str );
	void OnTimerProgress();
	void OnTimerCall();

	void UsersDirectoryLoad(bool update = false);
	afx_msg LRESULT onUsersDirectoryLoaded(WPARAM wParam,LPARAM lParam);
	LRESULT onShortcutsURLLoaded(WPARAM wParam, LPARAM lParam);
	void ShortcutsURLLoad();
	afx_msg LRESULT onCustomLoaded(WPARAM wParam, LPARAM lParam);
	void SetupJumpList();
	void RemoveJumpList();
	void MainPopupMenu(bool isMenuButton = false);
	void SetPaneText2(CString str = _T(""));
	void AccountSettingsPendingSave();
	void OnAccountChanged();
	void OpenTransferDlg(CWnd *pParent, msip_action action, pjsua_call_id call_id = PJSUA_INVALID_ID, Contact *selectedContact = NULL);
	void UpdateSoundDevicesIds();
	void PlayerStop();
#ifdef _GLOBAL_VIDEO
	Preview* previewWin;
	int VideoCaptureDeviceId(CString name=_T(""));
#endif
	void MessagesIncoming(CString* number, CString* message, CTime* pTime = NULL);

	bool CommandCallAnswer();
	bool CommandCallReject();
	bool CommandCallPickup(CString number);

protected:
	virtual void DoDataExchange(CDataExchange* pDX);	// DDX/DDV support

	// Implementation
protected:
	HICON m_hIcon;
	HICON iconSmall;
	HICON iconInactive;
	HICON iconMissed;
	NOTIFYICONDATA tnd;
	StatusBar m_bar;
	CMMNotificationClient *mmNotificationClient;

	unsigned char m_tabPrev;

	DWORD m_lastInputTime;
	int m_idleCounter;
	pjrpid_activity m_PresenceStatus;
	bool newMessages;
		
	afx_msg int OnCreate(LPCREATESTRUCT lpCreateStruct);
	afx_msg void OnDestroy();
	virtual BOOL OnInitDialog();
	virtual void PostNcDestroy();
	virtual LRESULT WindowProc(UINT message, WPARAM wParam, LPARAM lParam);
	virtual BOOL PreTranslateMessage(MSG* pMsg);

	// Generated message map functions
	afx_msg LRESULT OnUpdateWindowText(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onTrayNotify(WPARAM, LPARAM);
	afx_msg LRESULT onCreateRingingDlg(WPARAM, LPARAM);
	afx_msg LRESULT onRefreshLevels(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onRegState2(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onCallState(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onIncomingCall(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onMWIInfo(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onCallMediaState(WPARAM, LPARAM);
	afx_msg LRESULT onCallTransferStatus(WPARAM, LPARAM);
	afx_msg LRESULT onPager(WPARAM, LPARAM);
	afx_msg LRESULT onPagerStatus(WPARAM, LPARAM);
	afx_msg LRESULT onBuddyState(WPARAM, LPARAM);
	afx_msg LRESULT onCopyData(WPARAM, LPARAM);
	afx_msg LRESULT CreationComplete(WPARAM, LPARAM);
	DECLARE_MESSAGE_MAP()
public:
	afx_msg LRESULT OnNetworkChange(WPARAM, LPARAM);
	afx_msg LRESULT OnPowerBroadcast(WPARAM, LPARAM);
	afx_msg void OnSysCommand(UINT nID, LPARAM lParam);
	afx_msg BOOL OnQueryEndSession();
	afx_msg void OnBnClickedOk();
	afx_msg void OnBnClickedMenu();
	afx_msg void OnClose();
	afx_msg HBRUSH OnCtlColor(CDC* pDC, CWnd *pWnd, UINT nCtlColor);
	afx_msg void OnContextMenu(CWnd *pWnd, CPoint point );
	afx_msg BOOL OnDeviceChange(UINT nEventType, DWORD_PTR dwData);
	afx_msg void OnSessionChange(UINT nSessionState, UINT nId);
	afx_msg void OnMove(int x, int y);
	afx_msg void OnSize(UINT type, int w, int h);
	afx_msg LRESULT onShellHookMessage(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onCallAnswer(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onCallHangup(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onTabIconUpdate(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onSetPaneText(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onPlayerPlay(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onPlayerStop(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT onCommandLine(WPARAM wParam,LPARAM lParam);
	afx_msg LRESULT OnAccount(WPARAM wParam,LPARAM lParam);
	afx_msg void OnMenuAccountAdd();
	afx_msg void OnMenuAccountChange(UINT nID);
	afx_msg void OnMenuAccountEdit(UINT nID);
	afx_msg void OnMenuAccountLocalEdit();
	afx_msg void OnMenuCustomRange(UINT nID);
	afx_msg void OnMenuSettings();
	afx_msg void OnMenuShortcuts();
	afx_msg void OnMenuAlwaysOnTop();
	afx_msg void OnMenuLog();
	afx_msg void OnMenuExit();
	afx_msg void OnTimer (UINT_PTR TimerVal);
	afx_msg void OnTcnSelchangeTab(NMHDR *pNMHDR, LRESULT *pResult);
	afx_msg void OnTcnSelchangingTab(NMHDR *pNMHDR, LRESULT *pResult);
	afx_msg void OnMenuWebsite();
	afx_msg void OnMenuHelp();
	afx_msg void OnMenuAddl();
	afx_msg void OnMuteInput();
	afx_msg void OnMuteOutput();
	afx_msg void OnCheckUpdates();
	afx_msg void CheckUpdates();
	afx_msg LRESULT OnUpdateCheckerLoaded(WPARAM wParam, LPARAM lParam);
#ifdef _GLOBAL_VIDEO
	afx_msg void createPreviewWin();
#endif
	afx_msg	void OnUpdatePane(CCmdUI* pCmdUI);
};

extern CmainDlg *mainDlg;
void on_buddy_state(pjsua_buddy_id buddy_id);