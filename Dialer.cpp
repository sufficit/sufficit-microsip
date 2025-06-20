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

#include "StdAfx.h"
#include "Dialer.h"
#include "global.h"
#include "settings.h"
#include "mainDlg.h"
#include "microsip.h"
#include "Strsafe.h"
#include "langpack.h"
#include "Hid.h"
#include "afxbutton.h"

static CString digitsDTMFDelayed;

static UINT_PTR blinkTimer = NULL;
static bool blinkState = false;

Dialer::Dialer(CWnd* pParent /*=NULL*/)
	: CBaseDialog(Dialer::IDD, pParent)
{
	delayedDTMF = false;
	m_hasVoicemail = false;
	m_isButtonVoicemailVisible = false;
	Create(IDD, pParent);
}

Dialer::~Dialer(void)
{
}

void Dialer::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
	DDX_Control(pDX, IDC_DIALER_VOICEMAIL, m_ButtonVoicemail);
	DDX_Control(pDX, IDC_DIALER_VOICEMAIL_DISABLED, m_ButtonVoicemailDisabled);
	DDX_Control(pDX, IDC_VOLUME_INPUT, m_SliderCtrlInput);
	DDX_Control(pDX, IDC_VOLUME_OUTPUT, m_SliderCtrlOutput);
	DDX_Control(pDX, IDC_BUTTON_MINUS_INPUT, m_ButtonMinusInput);
	DDX_Control(pDX, IDC_BUTTON_MINUS_OUTPUT, m_ButtonMinusOutput);
	DDX_Control(pDX, IDC_BUTTON_PLUS_INPUT, m_ButtonPlusInput);
	DDX_Control(pDX, IDC_BUTTON_PLUS_OUTPUT, m_ButtonPlusOutput);

	DDX_Control(pDX, IDC_KEY_1, m_ButtonDialer1);
	DDX_Control(pDX, IDC_KEY_2, m_ButtonDialer2);
	DDX_Control(pDX, IDC_KEY_3, m_ButtonDialer3);
	DDX_Control(pDX, IDC_KEY_4, m_ButtonDialer4);
	DDX_Control(pDX, IDC_KEY_5, m_ButtonDialer5);
	DDX_Control(pDX, IDC_KEY_6, m_ButtonDialer6);
	DDX_Control(pDX, IDC_KEY_7, m_ButtonDialer7);
	DDX_Control(pDX, IDC_KEY_8, m_ButtonDialer8);
	DDX_Control(pDX, IDC_KEY_9, m_ButtonDialer9);
	DDX_Control(pDX, IDC_KEY_0, m_ButtonDialer0);
	DDX_Control(pDX, IDC_KEY_STAR, m_ButtonDialerStar);
	DDX_Control(pDX, IDC_KEY_GRATE, m_ButtonDialerGrate);
	DDX_Control(pDX, IDC_REDIAL, m_ButtonDialerRedial);
	DDX_Control(pDX, IDC_DELETE, m_ButtonDialerDelete);
	DDX_Control(pDX, IDC_KEY_PLUS, m_ButtonDialerPlus);
	DDX_Control(pDX, IDC_CLEAR, m_ButtonDialerClear);
	DDX_Control(pDX, IDC_CALL, m_ButtonCall);
	DDX_Control(pDX, IDC_END, m_ButtonEnd);
}

void Dialer::RebuildShortcuts(bool init)
{
	if (!init) {
		POSITION pos = shortcutButtons.GetHeadPosition();
		while (pos) {
			POSITION posKey = pos;
			CButton* button = shortcutButtons.GetNext(pos);
			AutoUnmove(button->m_hWnd);
			delete button;
			shortcutButtons.RemoveAt(posKey);
		};
	}
	if (!mainDlg->shortcutsEnabled) {
		return;
	}
	CRect windowRect;
	if (!init) {
		GetWindowRect(windowRect);
		SetWindowPos(NULL, 0, 0, windowSize.x, windowSize.y, SWP_NOZORDER | SWP_NOMOVE);
	}
	if (shortcuts.GetCount()) {
		CRect shortcutsRect;
		GetWindowRect(shortcutsRect);
		ScreenToClient(shortcutsRect);
		CRect rectLast;
		GetDlgItem(IDC_DIALER_LAST)->GetWindowRect(&rectLast);
		ScreenToClient(rectLast);
		CRect mapRect;
		int rowsMax = 12;
		int buttonHeight;
		int moveFactor;
		int moveFix;
		if (mainDlg->shortcutsBottom) {
			mapRect.left = 4;
			MapDialogRect(&mapRect);
			shortcutsRect.top = rectLast.bottom;
			shortcutsRect.left += mapRect.left;
			shortcutsRect.right -= mapRect.left;
			buttonHeight = MulDiv(25, dpiY, 96);
			moveFactor = 0;
			rowsMax = _GLOBAL_SHORTCUTS_QTY / 2;
		}
		else {
			mapRect.left = 4;
			mapRect.top = 2;
			mapRect.bottom = 1;
			MapDialogRect(&mapRect);
			shortcutsRect.top += mapRect.top;
			shortcutsRect.bottom -= mapRect.bottom;
			shortcutsRect.left = shortcutsRect.right - mainDlg->widthAdd;
			shortcutsRect.right -= mapRect.left;
			moveFactor = 100;
			if (shortcuts.GetCount() > rowsMax) {
				int count = shortcuts.GetCount() / 2 + shortcuts.GetCount() % 2;
				buttonHeight = shortcutsRect.Height() / count;
				shortcutsRect.top = shortcutsRect.top + (shortcutsRect.Height() - buttonHeight * count) / 2;
				moveFactor = moveFactor / count;
			}
			else {
				buttonHeight = shortcutsRect.Height() / shortcuts.GetCount();
				shortcutsRect.top = shortcutsRect.top + (shortcutsRect.Height() - buttonHeight * shortcuts.GetCount()) / 2;
				moveFactor = moveFactor / shortcuts.GetCount();
			}
		}
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut shortcut = shortcuts.GetAt(i);
			CMFCButton* button = new CMFCButton();
			//CButton* button = new CButton();
			int style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | DS_SETFONT;
			if (!shortcut.number2.IsEmpty()) {
				style |= BS_AUTOCHECKBOX;
			}
			else {
				//style |= BS_CHECKBOX;
			}
			if (mainDlg->shortcutsBottom) {
				CRect buttonRect;
				if (shortcuts.GetCount() > rowsMax) {
					int row = i % 2;
					buttonRect = CRect(shortcutsRect.left + row * shortcutsRect.Width() / 2, shortcutsRect.top, shortcutsRect.right - (1 - row) * shortcutsRect.Width() / 2, shortcutsRect.top + buttonHeight);
					button->Create(Translate(shortcut.label.GetBuffer()), style, buttonRect, this, IDC_SHORTCUT_RANGE + i);
					if (!row) {
						AutoMove(button->m_hWnd, 0, 100, 50, 0);
					}
					else {
						AutoMove(button->m_hWnd, 50, 100, 50, 0);
						shortcutsRect.top += buttonHeight;
					}
				}
				else {
					buttonRect = CRect(shortcutsRect.left, shortcutsRect.top, shortcutsRect.right, shortcutsRect.top + buttonHeight);
					button->Create(Translate(shortcut.label.GetBuffer()), style, buttonRect, this, IDC_SHORTCUT_RANGE + i);
					AutoMove(button->m_hWnd, 0, 100, 100, 0);

					shortcutsRect.top += buttonHeight;
				}
			}
			else {
				CRect buttonRect;
				if (shortcuts.GetCount() > rowsMax) {
					int row = i % 2;
					buttonRect = CRect(shortcutsRect.left + (row * MulDiv(97, dpiY, 96)), shortcutsRect.top, shortcutsRect.right - (1 - row) * MulDiv(97, dpiY, 96), shortcutsRect.top + buttonHeight);
					button->Create(Translate(shortcut.label.GetBuffer()), style, buttonRect, this, IDC_SHORTCUT_RANGE + i);
					AutoMove(button->m_hWnd, 100, i / 2 * moveFactor, 0, moveFactor);
					if (row) {
						shortcutsRect.top += buttonHeight;
					}
				}
				else {
					buttonRect = CRect(shortcutsRect.left, shortcutsRect.top, shortcutsRect.right, shortcutsRect.top + buttonHeight);
					button->Create(Translate(shortcut.label.GetBuffer()), style, buttonRect, this, IDC_SHORTCUT_RANGE + i);
					AutoMove(button->m_hWnd, 100, i * moveFactor, 0, moveFactor);
					shortcutsRect.top += buttonHeight;
				}
			}
			if (shortcut.presence) {
				shortcut.image = MSIP_CONTACT_ICON_DEFAULT;
				button->SetIcon(
					mainDlg->imageListStatus->ExtractIcon(shortcut.image)
				);
			}
			button->SetFont(&m_font_shortcuts);
			shortcutButtons.AddTail(button);
		}
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut* shortcut = &shortcuts.GetAt(i);
			if (shortcut->presence) {
				mainDlg->SubsribeNumber(&shortcut->number);
			}
		}
	}
	if (!init) {
		SetWindowPos(NULL, 0, 0, windowRect.Width(), windowRect.Height(), SWP_NOZORDER | SWP_NOMOVE);
	}
}

void Dialer::PresenceSubscribe()
{
	if (shortcuts.GetCount() == shortcutButtons.GetCount()) {
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut* shortcut = &shortcuts.GetAt(i);
			if (shortcut->presence) {
				mainDlg->SubsribeNumber(&shortcut->number);
			}
		}
	}
}

void Dialer::PresenceReset()
{
	if (!::IsWindow(this->m_hWnd)) {
		return;
	}
	if (shortcuts.GetCount() == shortcutButtons.GetCount()) {
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut* shortcut = &shortcuts.GetAt(i);
			if (shortcut->presence) {
				shortcut->image = MSIP_CONTACT_ICON_DEFAULT;
				shortcut->ringing = false;
				POSITION pos = shortcutButtons.FindIndex(i);
				CButton* button = shortcutButtons.GetAt(pos);
				if (::IsWindow(button->m_hWnd)) {
					button->SetIcon(mainDlg->imageListStatus->ExtractIcon(shortcut->image));
					//button->RedrawWindow();!!
					button->Invalidate();
				}
			}
		}
	}
}

void Dialer::PresenceReceived(CString* buddyNumber, int image, bool ringing, bool fromUsersDirectory)
{
	if (shortcuts.GetCount() == shortcutButtons.GetCount()) {
		bool blink = false;
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut* shortcut = &shortcuts.GetAt(i);
			if (shortcut->presence || fromUsersDirectory) {
				CString numberFormated;
				if (fromUsersDirectory) {
					numberFormated = shortcut->number;
				}
				else {
					CString commands;
					numberFormated = FormatNumber(shortcut->number, &commands, true);
				}
				if (*buddyNumber == numberFormated) {
					if (ringing) {
						blink = true;
					}
					shortcut->image = image;
					shortcut->ringing = ringing;
					POSITION pos = shortcutButtons.FindIndex(i);
					CButton* button = shortcutButtons.GetAt(pos);
					if (::IsWindow(button->m_hWnd)) {
						button->SetIcon(mainDlg->imageListStatus->ExtractIcon(shortcut->image));
						//button->RedrawWindow(); causes freezing
						button->Invalidate();
					}
				}
			}
		}
		if (blink) {
			if (!blinkTimer) {
				blinkTimer = SetTimer(IDT_TIMER_SHORTCUTS_BLINK, 500, NULL);
				OnTimerShortcutsBlink();
			}
		}
	}
}

void Dialer::OnTimerShortcutsBlink()
{
	if (!blinkTimer) {
		return;
	}
	bool ringing = false;
	if (shortcuts.GetCount() == shortcutButtons.GetCount()) {
		for (int i = 0; i < shortcuts.GetCount(); i++) {
			Shortcut* shortcut = &shortcuts.GetAt(i);
			if (shortcut->ringing) {
				ringing = true;
				POSITION pos = shortcutButtons.FindIndex(i);
				CButton* button = shortcutButtons.GetAt(pos);
				if (::IsWindow(button->m_hWnd)) {
					button->SetIcon(mainDlg->imageListStatus->ExtractIcon(blinkState ? shortcut->image : MSIP_CONTACT_ICON_BLANK));
					//button->RedrawWindow();// crash on VM ?
					button->Invalidate();
				}
			}
		}
	}
	if (!ringing) {
		blinkTimer = NULL;
		KillTimer(IDT_TIMER_CONTACTS_BLINK);
		blinkState = false;
	}
	else {
		blinkState = !blinkState;
	}
}

BOOL Dialer::OnInitDialog()
{
	CBaseDialog::OnInitDialog();
	if (langPack.rtl) {
		m_SliderCtrlOutput.ModifyStyleEx(0, WS_EX_LAYOUTRTL);
		m_SliderCtrlInput.ModifyStyleEx(0, WS_EX_LAYOUTRTL);
		GetDlgItem(IDC_NUMBER)->ModifyStyleEx(0, WS_EX_LAYOUTRTL);
	}

	CRect windowRect;
	GetWindowRect(windowRect);
	windowSize.x = windowRect.Width();
	windowSize.y = windowRect.Height();

	m_hCursorHand = ::LoadCursor(NULL, IDC_HAND);
	CFont* font = this->GetFont();
	LOGFONT lf;
	font->GetLogFont(&lf);

	lf.lfHeight = -MulDiv(11, dpiY, 96);
	m_font_shortcuts.CreateFontIndirect(&lf);

	RebuildShortcuts(true);

	TranslateDialog(this->m_hWnd);

	m_ButtonVoicemail.LoadBitmaps(IDB_VMAIL_100, IDB_VMAIL_DOWN_100, IDB_VMAIL_FOCUS_100);
	m_ButtonVoicemailDisabled.LoadBitmaps(IDB_VMAIL_GREY_100, IDB_VMAIL_GREY_DOWN_100, IDB_VMAIL_GREY_FOCUS_100);
	m_ButtonVoicemail.SizeToContent();
	m_ButtonVoicemailDisabled.SizeToContent();

	if (m_ToolTip.Create(this)) {
		m_ToolTip.AddTool(&m_ButtonDialerRedial, Translate(_T("Redial")));
		m_ToolTip.AddTool(&m_ButtonDialerDelete, Translate(_T("Backspace")));
		m_ToolTip.AddTool(&m_ButtonDialerClear, Translate(_T("Clear")));
	if (accountSettings.recordingButton) {
		m_ToolTip.AddTool(&m_ButtonRec, Translate(_T("Call Recording")));
	}
		CString str = Translate(_T("Voicemail Number"));
		m_ToolTip.AddTool(&m_ButtonVoicemail, str);
		m_ToolTip.AddTool(&m_ButtonVoicemailDisabled, str);
		m_ToolTip.Activate(TRUE);
	}

	RebuildButtons(true);
	AutoMove(IDC_NUMBER, 0, 0, 100, 0);
	AutoMove(IDC_DIALER_DTMF, 100, 0, 0, 0);

	int height = 17;
	int height4 = height * 4;
	int height2 = height * 2;
	int height3 = height * 3;
	AutoMove(IDC_KEY_1, 0, 0, 33, height);
	AutoMove(IDC_KEY_4, 0, height, 33, height);
	AutoMove(IDC_KEY_7, 0, height2, 33, height);
	AutoMove(IDC_KEY_STAR, 0, height3, 33, height);
	AutoMove(IDC_REDIAL, 0, height4, 33, height);
	AutoMove(IDC_DELETE, 0, height4, 33, 17);

	AutoMove(IDC_KEY_2, 33, 0, 34, height);
	AutoMove(IDC_KEY_5, 33, height, 34, height);
	AutoMove(IDC_KEY_8, 33, height2, 34, height);
	AutoMove(IDC_KEY_0, 33, height3, 34, height);
	AutoMove(IDC_KEY_PLUS, 33, height4, 34, height);
	AutoMove(IDC_KEY_3, 67, 0, 33, height);
	AutoMove(IDC_KEY_6, 67, height, 33, height);
	AutoMove(IDC_KEY_9, 67, height2, 33, height);
	AutoMove(IDC_KEY_GRATE, 67, height3, 33, height);
	AutoMove(IDC_CLEAR, 67, height4, 33, height);

#ifdef _GLOBAL_VIDEO
	AutoMove(IDC_VIDEO_CALL, 0, 85, 14, 15);
	AutoMove(IDC_CALL, 14, 85, 72, 15);
	AutoMove(IDC_MESSAGE, 86, 85, 14, 15);
#else
	AutoMove(IDC_CALL, 0, 85, 84, 15);
	AutoMove(IDC_MESSAGE, 84, 85, 16, 15);
#endif

	AutoMove(IDC_END, 14, 85, 72, 15);
	AutoMove(IDC_HOLD, 0, 85, 14, 15);
	AutoMove(IDC_TRANSFER, 86, 85, 14, 15);

	AutoMove(IDC_BUTTON_MUTE_OUTPUT, 0, 100, 0, 0);
	AutoMove(IDC_BUTTON_MUTE_INPUT, 0, 100, 0, 0);
	AutoMove(IDC_VOLUME_INPUT, 0, 100, 100, 0);
	AutoMove(IDC_VOLUME_OUTPUT, 0, 100, 100, 0);
	AutoMove(IDC_BUTTON_MINUS_INPUT, 0, 100, 0, 0);
	AutoMove(IDC_BUTTON_MINUS_OUTPUT, 0, 100, 0, 0);
	AutoMove(IDC_BUTTON_PLUS_INPUT, 100, 100, 0, 0);
	AutoMove(IDC_BUTTON_PLUS_OUTPUT, 100, 100, 0, 0);
	AutoMove(IDC_DIALER_VOICEMAIL, 100, 100, 0, 0);
	AutoMove(IDC_DIALER_VOICEMAIL_DISABLED, 100, 100, 0, 0);

	DialedLoad();

	//--
	lf.lfHeight = -MulDiv(13, dpiY, 96);
	m_font_call.CreateFontIndirect(&lf);
	//--
	lf.lfHeight = -MulDiv(19, dpiY, 96);
	m_font.CreateFontIndirect(&lf);
	//--
	m_font_number.CreateFontIndirect(&lf);
	//--
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	combobox->SetWindowPos(NULL, 0, 0, combobox->GetDroppedWidth(), MulDiv(400, dpiY, 96), SWP_NOZORDER | SWP_NOMOVE);
	combobox->SetFont(&m_font_number);
	GetDlgItem(IDC_KEY_1)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_2)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_3)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_4)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_5)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_6)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_7)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_8)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_9)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_0)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_STAR)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_GRATE)->SetFont(&m_font);
	GetDlgItem(IDC_KEY_PLUS)->SetFont(&m_font);
	GetDlgItem(IDC_CLEAR)->SetFont(&m_font);
	GetDlgItem(IDC_REDIAL)->SetFont(&m_font);
	GetDlgItem(IDC_DELETE)->SetFont(&m_font);

	m_ButtonCall.m_FaceColor = _GLOBAL_DIALER_CALL_COLOR;
	m_ButtonCall.m_TextColor = RGB(255, 255, 255);
	m_ButtonEnd.m_FaceColor = _GLOBAL_DIALER_END_COLOR;
	m_ButtonEnd.m_TextColor = RGB(255, 255, 255);
	m_ButtonEnd.EnableWindow(m_ButtonEnd.IsWindowEnabled());
	m_ButtonCall.SetFont(&m_font_call);
	m_ButtonEnd.SetFont(&m_font_call);
	m_ButtonEnd.ShowWindow(SW_HIDE);
	m_ButtonEnd.EnableWindow(TRUE);

	muteOutput = FALSE;
	muteInput = FALSE;

	m_SliderCtrlOutput.SetRange(0, 100);
	m_SliderCtrlOutput.SetPos(accountSettings.volumeOutput);

	m_SliderCtrlInput.SetRange(0, 100);
	m_SliderCtrlInput.SetPos(accountSettings.volumeInput);

	m_hIconMuteOutput = LoadImageIcon(IDI_MUTE_OUTPUT, 16, 16);
	((CButton*)GetDlgItem(IDC_BUTTON_MUTE_OUTPUT))->SetIcon(m_hIconMuteOutput);
	m_hIconMutedOutput = LoadImageIcon(IDI_MUTED_OUTPUT, 16, 16);

	m_hIconMuteInput = LoadImageIcon(IDI_MUTE_INPUT, 16, 16);
	((CButton*)GetDlgItem(IDC_BUTTON_MUTE_INPUT))->SetIcon(m_hIconMuteInput);
	m_hIconMutedInput = LoadImageIcon(IDI_MUTED_INPUT, 16, 16);

	m_hIconHold = LoadImageIcon(IDI_HOLD, 16, 16);
	m_hIconResume = LoadImageIcon(IDI_RESUME, 16, 16);
	((CButton*)GetDlgItem(IDC_HOLD))->SetIcon(m_hIconHold);
	m_hIconTransfer = LoadImageIcon(IDI_TRANSFER, 16, 16);
	((CButton*)GetDlgItem(IDC_TRANSFER))->SetIcon(m_hIconTransfer);
#ifdef _GLOBAL_VIDEO
	m_hIconVideo = LoadImageIcon(IDI_VIDEO, 16, 16);
	((CButton*)GetDlgItem(IDC_VIDEO_CALL))->SetIcon(m_hIconVideo);
#endif
	m_hIconMessage = LoadImageIcon(IDI_MESSAGE, 16, 16);
	((CButton*)GetDlgItem(IDC_MESSAGE))->SetIcon(m_hIconMessage);

	UpdateCallButton();

return TRUE;
}

int Dialer::OnCreate(LPCREATESTRUCT lpCreateStruct)
{
	if (mainDlg->widthAdd || mainDlg->heightAdd) {
		SetWindowPos(NULL, 0, 0, lpCreateStruct->cx + mainDlg->widthAdd, lpCreateStruct->cy + mainDlg->heightAdd, SWP_NOMOVE | SWP_NOZORDER);
	}
	if (langPack.rtl) {
		ModifyStyleEx(WS_EX_LAYOUTRTL, 0);
	}
	return CBaseDialog::OnCreate(lpCreateStruct);
}

void Dialer::OnDestroy()
{
	KillTimer(IDT_TIMER_VU_METER);
	CBaseDialog::OnDestroy();
}

void Dialer::PostNcDestroy()
{
	CBaseDialog::PostNcDestroy();
	delete this;
}

BEGIN_MESSAGE_MAP(Dialer, CBaseDialog)
	ON_BN_CLICKED(IDOK, OnBnClickedOk)
	ON_BN_CLICKED(IDCANCEL, OnBnClickedCancel)
	ON_WM_SETCURSOR()
	ON_WM_CTLCOLOR()
	ON_BN_CLICKED(IDC_DIALER_DND, &Dialer::OnBnClickedDND)
	ON_BN_CLICKED(IDC_DIALER_FWD, &Dialer::OnBnClickedFWD)
	ON_BN_CLICKED(IDC_DIALER_AA, &Dialer::OnBnClickedAA)
	ON_BN_CLICKED(IDC_DIALER_AC, &Dialer::OnBnClickedAC)
	ON_BN_CLICKED(IDC_DIALER_CONF, &Dialer::OnBnClickedConf)
	ON_BN_CLICKED(IDC_DIALER_REC, &Dialer::OnBnClickedRec)
	ON_BN_CLICKED(IDC_DIALER_VOICEMAIL, OnBnClickedVoicemail)
	ON_BN_CLICKED(IDC_DIALER_VOICEMAIL_DISABLED, OnBnClickedVoicemail)
	ON_BN_CLICKED(IDC_BUTTON_PLUS_INPUT, &Dialer::OnBnClickedPlusInput)
	ON_BN_CLICKED(IDC_BUTTON_MINUS_INPUT, &Dialer::OnBnClickedMinusInput)
	ON_BN_CLICKED(IDC_BUTTON_PLUS_OUTPUT, &Dialer::OnBnClickedPlusOutput)
	ON_BN_CLICKED(IDC_BUTTON_MINUS_OUTPUT, &Dialer::OnBnClickedMinusOutput)
	ON_BN_CLICKED(IDC_BUTTON_MUTE_OUTPUT, &Dialer::OnBnClickedMuteOutput)
	ON_BN_CLICKED(IDC_BUTTON_MUTE_INPUT, &Dialer::OnBnClickedMuteInput)
	ON_COMMAND_RANGE(IDC_SHORTCUT_RANGE, IDC_SHORTCUT_RANGE + 24, &Dialer::OnBnClickedShortcut)
	ON_WM_RBUTTONUP()
	ON_WM_LBUTTONUP()
	ON_WM_MOUSEMOVE()

	ON_BN_CLICKED(IDC_CALL, OnBnClickedCall)
	ON_BN_CLICKED(IDC_DIALER_DTMF, OnBnClickedDTMF)
#ifdef _GLOBAL_VIDEO
	ON_BN_CLICKED(IDC_VIDEO_CALL, OnBnClickedVideoCall)
#endif
	ON_BN_CLICKED(IDC_MESSAGE, OnBnClickedMessage)
	ON_BN_CLICKED(IDC_HOLD, OnBnClickedHold)
	ON_BN_CLICKED(IDC_TRANSFER, OnBnClickedTransfer)
	ON_BN_CLICKED(IDC_END, OnBnClickedEnd)
	ON_CBN_EDITCHANGE(IDC_NUMBER, &Dialer::OnCbnEditchangeComboAddr)
	ON_CBN_SELCHANGE(IDC_NUMBER, &Dialer::OnCbnSelchangeComboAddr)

	ON_BN_CLICKED(IDC_KEY_1, &Dialer::OnBnClickedKey1)
	ON_BN_CLICKED(IDC_KEY_2, &Dialer::OnBnClickedKey2)
	ON_BN_CLICKED(IDC_KEY_3, &Dialer::OnBnClickedKey3)
	ON_BN_CLICKED(IDC_KEY_4, &Dialer::OnBnClickedKey4)
	ON_BN_CLICKED(IDC_KEY_5, &Dialer::OnBnClickedKey5)
	ON_BN_CLICKED(IDC_KEY_6, &Dialer::OnBnClickedKey6)
	ON_BN_CLICKED(IDC_KEY_7, &Dialer::OnBnClickedKey7)
	ON_BN_CLICKED(IDC_KEY_8, &Dialer::OnBnClickedKey8)
	ON_BN_CLICKED(IDC_KEY_9, &Dialer::OnBnClickedKey9)
	ON_BN_CLICKED(IDC_KEY_STAR, &Dialer::OnBnClickedKeyStar)
	ON_BN_CLICKED(IDC_KEY_0, &Dialer::OnBnClickedKey0)
	ON_BN_CLICKED(IDC_KEY_GRATE, &Dialer::OnBnClickedKeyGrate)
	ON_BN_CLICKED(IDC_REDIAL, &Dialer::OnBnClickedRedial)
	ON_BN_CLICKED(IDC_DELETE, &Dialer::OnBnClickedDelete)
	ON_BN_CLICKED(IDC_KEY_PLUS, &Dialer::OnBnClickedKeyPlus)
	ON_BN_CLICKED(IDC_CLEAR, &Dialer::OnBnClickedClear)
	ON_WM_HSCROLL()
	ON_WM_CREATE()
	ON_WM_DESTROY()
	ON_WM_TIMER()
END_MESSAGE_MAP()

void Dialer::SetName(CString str)
{
}

void Dialer::UpdateVoicemailButton(bool hasMail)
{
	if (m_hasVoicemail != hasMail) {
		m_hasVoicemail = hasMail;
	}
	if (m_isButtonVoicemailVisible) {
		if (hasMail) {
			m_ButtonVoicemailDisabled.ShowWindow(SW_HIDE);
			m_ButtonVoicemail.ShowWindow(SW_SHOW);
		}
		else {
			m_ButtonVoicemail.ShowWindow(SW_HIDE);
			m_ButtonVoicemailDisabled.ShowWindow(SW_SHOW);
		}
	}
	else {
		m_ButtonVoicemail.ShowWindow(SW_HIDE);
		m_ButtonVoicemailDisabled.ShowWindow(SW_HIDE);
	}
}

void Dialer::RebuildButtons(bool init)
{

	if (accountSettings.accountId && !accountSettings.account.voicemailNumber.IsEmpty()) {
		m_isButtonVoicemailVisible = true;
		UpdateVoicemailButton(m_hasVoicemail);
	}
	else {
		m_isButtonVoicemailVisible = false;
		UpdateVoicemailButton(m_hasVoicemail);
	}
	if (IsChild(&m_ButtonDND)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonDND);
		}
		m_ButtonDND.DestroyWindow();
	}
	if (IsChild(&m_ButtonFWD)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonFWD);
		}
		m_ButtonFWD.DestroyWindow();
	}
	if (IsChild(&m_ButtonAA)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonAA);
		}
		m_ButtonAA.DestroyWindow();
	}
	if (IsChild(&m_ButtonAC)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonAC);
		}
		m_ButtonAC.DestroyWindow();
	}
	if (IsChild(&m_ButtonConf)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonConf);
		}
		m_ButtonConf.DestroyWindow();
	}
	if (IsChild(&m_ButtonRec)) {
		if (m_ToolTip) {
			m_ToolTip.DelTool(&m_ButtonRec);
		}
		m_ButtonRec.DestroyWindow();
	}
	bool addDND = accountSettings.denyIncoming == _T("button");
	bool addFWD = accountSettings.forwarding == _T("button") && !accountSettings.forwardingNumber.IsEmpty();
	bool addAA = accountSettings.autoAnswer == _T("button");
	bool addAC = !accountSettings.singleMode;
	bool addConf = true;
	
	bool addRec = accountSettings.recordingButton;
	if (addDND || addFWD || addAA || addAC || addConf || addRec) {
		CRect windowRect;
		if (!init) {
			GetWindowRect(windowRect);
			SetWindowPos(NULL, 0, 0, windowSize.x, windowSize.y, SWP_NOZORDER | SWP_NOMOVE);
		}

		CRect rect;
		m_ButtonVoicemail.GetWindowRect(&rect);
		ScreenToClient(rect);
		rect.top -= 1;
		rect.bottom += 1;
		//rect.left -= 1;
		//rect.right += 2;

		CRect mapRect;
		mapRect.top = 5;
		mapRect.bottom = 2;
		MapDialogRect(&mapRect);
		int stepPx = mapRect.bottom + rect.Width();

		if (m_isButtonVoicemailVisible) {
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addRec) {
			m_ButtonRec.Create(Translate(_T("REC")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_CHECKBOX | BS_PUSHLIKE | WS_DISABLED, rect, this, IDC_DIALER_REC);
			m_ButtonRec.SetFont(GetFont());
			AutoMove(m_ButtonRec.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonRec, Translate(_T("Call Recording")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addConf) {
			rect.left -= mapRect.top;
			m_ButtonConf.Create(Translate(_T("CONF")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHLIKE | WS_DISABLED, rect, this, IDC_DIALER_CONF);
			rect.right -= mapRect.top;
			m_ButtonConf.SetFont(GetFont());
			AutoMove(m_ButtonConf.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonConf, Translate(_T("Conference")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addAA) {
			m_ButtonAA.Create(Translate(_T("AA")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX | BS_PUSHLIKE, rect, this, IDC_DIALER_AA);
			m_ButtonAA.SetFont(GetFont());
			m_ButtonAA.SetCheck(accountSettings.AA ? BST_CHECKED : BST_UNCHECKED);
			AutoMove(m_ButtonAA.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonAA, Translate(_T("Auto Answer")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addAC) {
			m_ButtonAC.Create(Translate(_T("AC")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX | BS_PUSHLIKE, rect, this, IDC_DIALER_AC);
			m_ButtonAC.SetFont(GetFont());
			m_ButtonAC.SetCheck(accountSettings.AC ? BST_CHECKED : BST_UNCHECKED);
			AutoMove(m_ButtonAC.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonAC, Translate(_T("Auto Conference")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addFWD) {
			m_ButtonFWD.Create(Translate(_T("FWD")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX | BS_PUSHLIKE, rect, this, IDC_DIALER_FWD);
			m_ButtonFWD.SetFont(GetFont());
			m_ButtonFWD.SetCheck(accountSettings.FWD ? BST_CHECKED : BST_UNCHECKED);
			AutoMove(m_ButtonFWD.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonFWD, Translate(_T("Call Forwarding")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (addDND) {
			m_ButtonDND.Create(Translate(_T("DND")), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_CHECKBOX | BS_PUSHLIKE, rect, this, IDC_DIALER_DND);
			m_ButtonDND.SetFont(GetFont());
			m_ButtonDND.SetCheck(accountSettings.DND ? BST_CHECKED : BST_UNCHECKED);
			AutoMove(m_ButtonDND.m_hWnd, 100, 100, 0, 0);
			if (m_ToolTip) {
				m_ToolTip.AddTool(&m_ButtonDND, Translate(_T("Do Not Disturb")));
			}
			rect.left -= stepPx;
			rect.right -= stepPx;
		}
		if (!init) {
			SetWindowPos(NULL, 0, 0, windowRect.Width(), windowRect.Height(), SWP_NOZORDER | SWP_NOMOVE);
		}
	}
}

void Dialer::OnTimer(UINT_PTR TimerVal)
{
	if (TimerVal == IDT_TIMER_VU_METER) {
		TimerVuMeter();
	}
	if (TimerVal == IDT_TIMER_DTMF) {
		KillTimer(IDT_TIMER_DTMF);
		DTMF(digitsDTMFDelayed);
		digitsDTMFDelayed.Empty();
	}
	if (TimerVal == IDT_TIMER_SHORTCUTS_BLINK) {
		OnTimerShortcutsBlink();
	}
}

BOOL Dialer::PreTranslateMessage(MSG* pMsg)
{
	if (m_ToolTip) {
		m_ToolTip.RelayEvent(pMsg);
	}

	BOOL catched = FALSE;
	BOOL isEdit = FALSE;
	CEdit* edit = NULL;
	if (pMsg->message == WM_CHAR || (pMsg->message == WM_KEYDOWN && pMsg->wParam == VK_ESCAPE)) {
		CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
		edit = (CEdit*)FindWindowEx(combobox->m_hWnd, NULL, _T("EDIT"), NULL);
		isEdit = !edit || edit == GetFocus();
	}
	if (pMsg->message == WM_CHAR)
	{
		if (pMsg->wParam == 48)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_0));
				OnBnClickedKey0();
				catched = TRUE;
			}
			else {
				DTMF(_T("0"));
			}
		}
		else if (pMsg->wParam == 49)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_1));
				OnBnClickedKey1();
				catched = TRUE;
			}
			else {
				DTMF(_T("1"));
			}
		}
		else if (pMsg->wParam == 50)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_2));
				OnBnClickedKey2();
				catched = TRUE;
			}
			else {
				DTMF(_T("2"));
			}
		}
		else if (pMsg->wParam == 51)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_3));
				OnBnClickedKey3();
				catched = TRUE;
			}
			else {
				DTMF(_T("3"));
			}
		}
		else if (pMsg->wParam == 52)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_4));
				OnBnClickedKey4();
				catched = TRUE;
			}
			else {
				DTMF(_T("4"));
			}
		}
		else if (pMsg->wParam == 53)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_5));
				OnBnClickedKey5();
				catched = TRUE;
			}
			else {
				DTMF(_T("5"));
			}
		}
		else if (pMsg->wParam == 54)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_6));
				OnBnClickedKey6();
				catched = TRUE;
			}
			else {
				DTMF(_T("6"));
			}
		}
		else if (pMsg->wParam == 55)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_7));
				OnBnClickedKey7();
				catched = TRUE;
			}
			else {
				DTMF(_T("7"));
			}
		}
		else if (pMsg->wParam == 56)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_8));
				OnBnClickedKey8();
				catched = TRUE;
			}
			else {
				DTMF(_T("8"));
			}
		}
		else if (pMsg->wParam == 57)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_9));
				OnBnClickedKey9();
				catched = TRUE;
			}
			else {
				DTMF(_T("9"));
			}
		}
		else if (pMsg->wParam == 35 || pMsg->wParam == 47)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_GRATE));
				OnBnClickedKeyGrate();
				catched = TRUE;
			}
			else {
				DTMF(_T("#"));
			}
		}
		else if (pMsg->wParam == 42)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_STAR));
				OnBnClickedKeyStar();
				catched = TRUE;
			}
			else {
				DTMF(_T("*"));
			}
		}
		else if (pMsg->wParam == 43)
		{
			if (!isEdit) {
				GotoDlgCtrl(GetDlgItem(IDC_KEY_PLUS));
				OnBnClickedKeyPlus();
				catched = TRUE;
			}
		}
		else if (pMsg->wParam == 8 || pMsg->wParam == 45)
		{
			if (!isEdit)
			{
				GotoDlgCtrl(GetDlgItem(IDC_DELETE));
				OnBnClickedDelete();
				catched = TRUE;
			}
		}
		else if (pMsg->wParam == 46)
		{
			if (!isEdit)
			{
				Input(_T("."), TRUE);
				catched = TRUE;
			}
		}
	}
	else if (pMsg->message == WM_KEYDOWN) {
		if (pMsg->wParam == VK_ESCAPE) {
			WINDOWINFO wndInfo;
			m_ButtonEnd.GetWindowInfo(&wndInfo);
			bool isEndVisisble = wndInfo.dwStyle & WS_VISIBLE;
			if (accountSettings.singleMode && isEndVisisble) {
				OnBnClickedEnd();
				catched = TRUE;
			}
			else {
				if (!isEdit) {
					GotoDlgCtrl(GetDlgItem(IDC_NUMBER));
					catched = TRUE;
				}
				if (edit) {
					CString str;
					edit->GetWindowText(str);
					if (!str.IsEmpty()) {
						Clear();
						catched = TRUE;
					}
				}
			}
		}
	}
	if (!catched)
	{
		return CBaseDialog::PreTranslateMessage(pMsg);
	}
	else {
		return TRUE;
	}
}

HBRUSH Dialer::OnCtlColor(CDC* pDC, CWnd *pWnd, UINT nCtlColor)
{
	HBRUSH br = CBaseDialog::OnCtlColor(pDC, pWnd, nCtlColor);
	if (pWnd == &m_ButtonMinusInput
		|| pWnd == &m_ButtonMinusOutput
		|| pWnd == &m_ButtonPlusInput
		|| pWnd == &m_ButtonPlusOutput
		) {
		pDC->SetTextColor(RGB(127, 127, 127));
	}
	return br;
}


void Dialer::OnBnClickedOk()
{
	WINDOWINFO wndInfo;
	m_ButtonEnd.GetWindowInfo(&wndInfo);
	bool isEndVisisble = wndInfo.dwStyle & WS_VISIBLE;
	if (accountSettings.singleMode && isEndVisisble) {
		if (m_ButtonEnd.IsWindowEnabled()) {
			OnBnClickedEnd();
		}
	}
	else {
		OnBnClickedCall();
	}
}

void Dialer::OnBnClickedCancel()
{
	mainDlg->ShowWindow(SW_HIDE);
}

void Dialer::DTMFDelayed(CString digits, int delay)
{
	digitsDTMFDelayed = digits;
	SetTimer(IDT_TIMER_DTMF, delay, NULL);
}

void Dialer::DTMF(CString digits, bool force)
{
	bool delayed = false;
	if (digits.Right(1) == _T("?")) {
		digits = digits.Left(digits.GetLength() - 1);
		delayed = true;
	}
	pjsua_call_id call_id = PJSUA_INVALID_ID;
	MessagesContact*  messagesContact = mainDlg->messagesDlg->GetMessageContact();
	if (messagesContact && messagesContact->callId != -1) {
		call_id = messagesContact->callId;
		if (delayed) {
			SetDTMF(digits);
		}
	}
	if (!delayed) {
		WINDOWINFO wndInfo;
		GetDlgItem(IDC_DIALER_DTMF)->GetWindowInfo(&wndInfo);
		bool isButtonVisisble = wndInfo.dwStyle & WS_VISIBLE;
		if (isButtonVisisble && !force) {
			return;
		}
		msip_call_dial_dtmf(call_id, digits);
	}
}

void Dialer::SetDTMF(CString digits)
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	CRect rect;
	combobox->GetWindowRect(rect);
	
	CRect mapRect;
	mapRect.bottom = 45;
	MapDialogRect(&mapRect);

	WINDOWINFO wndInfo;
	GetDlgItem(IDC_DIALER_DTMF)->GetWindowInfo(&wndInfo);
	bool isButtonVisisble = wndInfo.dwStyle & WS_VISIBLE;

	if (!digits.IsEmpty()) {
		SetNumber(digits);
		if (!isButtonVisisble) {
			GetDlgItem(IDC_DIALER_DTMF)->ShowWindow(SW_SHOW);
			combobox->SetWindowPos(NULL, 0, 0, rect.Width() - mapRect.bottom, rect.Height(), SWP_NOZORDER | SWP_NOMOVE);
		}
	}
	else {
		CString old;
		combobox->GetWindowText(old);
		if (!old.IsEmpty()) {
			SetNumber(_T(""));
		}
		if (isButtonVisisble) {
			GetDlgItem(IDC_DIALER_DTMF)->ShowWindow(SW_HIDE);
			combobox->SetWindowPos(NULL, 0, 0, rect.Width() + mapRect.bottom, rect.Height(), SWP_NOZORDER | SWP_NOMOVE);
		}
	}
}

void Dialer::Input(CString digits, BOOL disableDTMF)
{
	if (!disableDTMF) {
		DTMF(digits);
	}
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	CEdit* edit = (CEdit*)FindWindowEx(combobox->m_hWnd, NULL, _T("EDIT"), NULL);
	if (edit) {
		int nLength = edit->GetWindowTextLength();
		edit->SetSel(nLength, nLength);
		edit->ReplaceSel(digits);
	}
}

void Dialer::DialedClear()
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	combobox->ResetContent();
	combobox->Clear();
}
void Dialer::DialedLoad()
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	CString key;
	CString val;
	LPTSTR ptr = val.GetBuffer(255);
	int i = 0;
	while (TRUE) {
		key.Format(_T("%d"), i);
		if (GetPrivateProfileString(_T("Dialed"), key, NULL, ptr, 256, accountSettings.iniFile)) {
			combobox->AddString(ptr);
		}
		else {
			break;
		}
		i++;
	}
}

void Dialer::DialedSave(CComboBox *combobox)
{
	CString key;
	CString val;
	WritePrivateProfileString(_T("Dialed"), NULL, NULL, accountSettings.iniFile);
	for (int i = 0; i < combobox->GetCount(); i++)
	{
		int n = combobox->GetLBTextLen(i);
		combobox->GetLBText(i, val.GetBuffer(n));
		val.ReleaseBuffer();

		key.Format(_T("%d"), i);
		WritePrivateProfileString(_T("Dialed"), key, val, accountSettings.iniFile);
	}
}

void Dialer::DialedAdd(CString number)
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	int pos = combobox->FindStringExact(-1, number);
	if (pos == CB_ERR || pos > 0) {
		if (pos > 0) {
			combobox->DeleteString(pos);
		}
		else if (combobox->GetCount() >= 10)
		{
			combobox->DeleteString(combobox->GetCount() - 1);
		}
		combobox->InsertString(0, number);
		combobox->SetCurSel(0);
	}
	DialedSave(combobox);
}

void Dialer::SetNumber(CString  number, int callsCount)
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	CString old;
	combobox->GetWindowText(old);
	if (old.IsEmpty() || number.Find(old) != 0) {
		combobox->SetWindowText(number);
	}
	UpdateCallButton(0, callsCount);
	delayedDTMF = false;
}

void Dialer::UpdateCallButton(BOOL forse, int callsCount)
{
	int len;
	if (!forse) {
		CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
		len = combobox->GetWindowTextLength();
	}
	else {
		len = 1;
	}
	bool state = false;
	if (accountSettings.singleMode) {
		if (callsCount == -1) {
			callsCount = mainDlg->messagesDlg->GetCallsCount();
		}
		bool isEndVisisble = false;
		WINDOWINFO wndInfo;
		m_ButtonEnd.GetWindowInfo(&wndInfo);
		isEndVisisble = wndInfo.dwStyle & WS_VISIBLE;
		if (callsCount) {
			if (!isEndVisisble) {
				m_ButtonCall.ShowWindow(SW_HIDE);
#ifdef _GLOBAL_VIDEO
				GetDlgItem(IDC_VIDEO_CALL)->ShowWindow(SW_HIDE);
#endif
				GetDlgItem(IDC_MESSAGE)->ShowWindow(SW_HIDE);
				GetDlgItem(IDC_HOLD)->ShowWindow(SW_SHOW);
				GetDlgItem(IDC_TRANSFER)->ShowWindow(SW_SHOW);
				m_ButtonEnd.ShowWindow(SW_SHOW);
				GotoDlgCtrl(GetDlgItem(IDC_END));
			}
		}
		else {
			if (isEndVisisble) {
				GetDlgItem(IDC_HOLD)->ShowWindow(SW_HIDE);
				GetDlgItem(IDC_TRANSFER)->ShowWindow(SW_HIDE);
				m_ButtonEnd.ShowWindow(SW_HIDE);

				m_ButtonCall.ShowWindow(SW_SHOW);
#ifdef _GLOBAL_VIDEO
				GetDlgItem(IDC_VIDEO_CALL)->ShowWindow(SW_SHOW);
#endif
				GetDlgItem(IDC_MESSAGE)->ShowWindow(SW_SHOW);
			}
		}
		state = callsCount || len ? true : false;

	}
	else {
		state = len ? true : false;
	}
	m_ButtonCall.EnableWindow(state);
#ifdef _GLOBAL_VIDEO
	if (accountSettings.disableVideo) {
		GetDlgItem(IDC_VIDEO_CALL)->EnableWindow(false);
	}
	else {
		GetDlgItem(IDC_VIDEO_CALL)->EnableWindow(state);
	}
#endif
	if (accountSettings.disableMessaging) {
		GetDlgItem(IDC_MESSAGE)->EnableWindow(false);
	}
	else {
		GetDlgItem(IDC_MESSAGE)->EnableWindow(state);
	}
	CButton *buttonRedial = (CButton *)GetDlgItem(IDC_REDIAL);
	CButton *buttonDelete = (CButton *)GetDlgItem(IDC_DELETE);
	if (!state) {
		buttonDelete->ShowWindow(SW_HIDE);
		buttonRedial->ShowWindow(SW_SHOW);
	}
	else {
		buttonRedial->ShowWindow(SW_HIDE);
		buttonDelete->ShowWindow(SW_SHOW);
	}
	if (!len) {
		SetDTMF(_T(""));
	}
}

void Dialer::Action(DialerActions action)
{
	CString number;
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	combobox->GetWindowText(number);
	number.Trim();
	if (!number.IsEmpty()) {
		bool res = false;
		if (action != ACTION_MESSAGE) {
			res = mainDlg->MakeCall(number, action == ACTION_VIDEO_CALL);
		}
		else {
			res = mainDlg->MessagesOpen(number);
		}
		if (res) {
			//-- save dialed in combobox
			DialedAdd(number);
			if (!accountSettings.singleMode) {
				Clear();
			}
			//-- end
		}
	}
}

void Dialer::Clear(bool update)
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	combobox->SetCurSel(-1);
	if (update) {
		UpdateCallButton();
	}
}

void Dialer::OnBnClickedCall()
{
	Action(ACTION_CALL);
}

void Dialer::OnBnClickedDTMF()
{
	CString number;
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	combobox->GetWindowText(number);
	number.Trim();
	if (!number.IsEmpty()) {
		DTMF(number, true);
		SetDTMF(_T(""));
	}
}

#ifdef _GLOBAL_VIDEO
void Dialer::OnBnClickedVideoCall()
{
	Action(ACTION_VIDEO_CALL);
}
#endif

void Dialer::OnBnClickedMessage()
{
	Action(ACTION_MESSAGE);
}

void Dialer::OnBnClickedHold()
{
	mainDlg->messagesDlg->OnBnClickedHold();
}

void Dialer::OnBnClickedTransfer()
{
	mainDlg->OpenTransferDlg(mainDlg, MSIP_ACTION_TRANSFER);
}

void Dialer::OnBnClickedEnd()
{
	MessagesContact*  messagesContact = mainDlg->messagesDlg->GetMessageContact();
	if (messagesContact && messagesContact->callId != -1) {
		msip_call_end(messagesContact->callId);
	}
	else {
		call_hangup_all_noincoming();
	}
}

void Dialer::OnCbnEditchangeComboAddr()
{
	UpdateCallButton();
}

void Dialer::OnCbnSelchangeComboAddr()
{
	UpdateCallButton(TRUE);
}

void Dialer::OnBnClickedKey1()
{
	Input(_T("1"));
}

void Dialer::OnBnClickedKey2()
{
	Input(_T("2"));
}

void Dialer::OnBnClickedKey3()
{
	Input(_T("3"));
}

void Dialer::OnBnClickedKey4()
{
	Input(_T("4"));
}

void Dialer::OnBnClickedKey5()
{
	Input(_T("5"));
}

void Dialer::OnBnClickedKey6()
{
	Input(_T("6"));
}

void Dialer::OnBnClickedKey7()
{
	Input(_T("7"));
}

void Dialer::OnBnClickedKey8()
{
	Input(_T("8"));
}

void Dialer::OnBnClickedKey9()
{
	Input(_T("9"));
}

void Dialer::OnBnClickedKeyStar()
{
	Input(_T("*"));
}

void Dialer::OnBnClickedKey0()
{
	Input(_T("0"));
}

void Dialer::OnBnClickedKeyGrate()
{
	Input(_T("#"));
}

void Dialer::OnBnClickedRedial()
{
	if (!accountSettings.lastCallNumber.IsEmpty()) {
		mainDlg->MakeCall(accountSettings.lastCallNumber, accountSettings.lastCallHasVideo, false, true);
	}
}

void Dialer::OnBnClickedDelete()
{
	CComboBox *combobox = (CComboBox*)GetDlgItem(IDC_NUMBER);
	CEdit* edit = (CEdit*)FindWindowEx(combobox->m_hWnd, NULL, _T("EDIT"), NULL);
	if (edit) {
		int nLength = edit->GetWindowTextLength();
		edit->SetSel(nLength - 1, nLength);
		edit->ReplaceSel(_T(""));
	}
}

void Dialer::OnBnClickedKeyPlus()
{
	Input(_T("+"), TRUE);
}

void Dialer::OnBnClickedClear()
{
	Clear();
}

void Dialer::OnLButtonUp(UINT nFlags, CPoint pt)
{
}

void Dialer::OnRButtonUp(UINT nFlags, CPoint pt)
{
}

void Dialer::OnMouseMove(UINT nFlags, CPoint pt)
{
}

void Dialer::MuteOutput(bool state)
{
	CButton *button = (CButton*)GetDlgItem(IDC_BUTTON_MUTE_OUTPUT);
	button->SetCheck(!state ? BST_CHECKED : BST_UNCHECKED);
	OnBnClickedMuteOutput();
}

void Dialer::MuteInput(bool state)
{
	CButton *button = (CButton*)GetDlgItem(IDC_BUTTON_MUTE_INPUT);
	button->SetCheck(!state ? BST_CHECKED : BST_UNCHECKED);
	OnBnClickedMuteInput();
}

void Dialer::OnHScroll(UINT, UINT, CScrollBar* sender)
{
	if (pj_ready) {
		int pos;
		if (!sender || sender == (CScrollBar*)&m_SliderCtrlOutput) {
			if (sender && muteOutput) {
				MuteOutput(false);
				return;
			}
			pos = m_SliderCtrlOutput.GetPos();
			//msip_audio_output_set_volume(pos,muteOutput);
			msip_audio_conf_set_volume(pos, muteOutput);
			accountSettings.volumeOutput = pos;
			mainDlg->AccountSettingsPendingSave();
		}
		if (!sender || sender == (CScrollBar*)&m_SliderCtrlInput) {
			if (sender && muteInput) {
				MuteInput(false);
				return;
			}
			pos = m_SliderCtrlInput.GetPos();
			msip_audio_input_set_volume(pos, muteInput);
			accountSettings.volumeInput = pos;
			mainDlg->AccountSettingsPendingSave();
		}
	}
}

void Dialer::OnBnClickedMinusInput()
{
	int pos = m_SliderCtrlInput.GetPos();
	if (pos > 0) {
		pos -= 5;
		if (pos < 0) {
			pos = 0;
		}
		m_SliderCtrlInput.SetPos(pos);
		OnHScroll(0, 0, (CScrollBar *)&m_SliderCtrlInput);
	}


}

void Dialer::OnBnClickedPlusInput()
{
	int pos = m_SliderCtrlInput.GetPos();
	if (pos < 100) {
		pos += 5;
		if (pos > 100) {
			pos = 100;
		}
		m_SliderCtrlInput.SetPos(pos);
		OnHScroll(0, 0, (CScrollBar *)&m_SliderCtrlInput);
	}
}

void Dialer::OnBnClickedMinusOutput()
{
	int pos = m_SliderCtrlOutput.GetPos();
	if (pos > 0) {
		pos -= 5;
		if (pos < 0) {
			pos = 0;
		}
		m_SliderCtrlOutput.SetPos(pos);
		OnHScroll(0, 0, (CScrollBar *)&m_SliderCtrlOutput);
	}
}

void Dialer::OnBnClickedPlusOutput()
{
	int pos = m_SliderCtrlOutput.GetPos();
	if (pos < 100) {
		pos += 5;
		if (pos > 100) {
			pos = 100;
		}
		m_SliderCtrlOutput.SetPos(pos);
		OnHScroll(0, 0, (CScrollBar *)&m_SliderCtrlOutput);
	}
}

void Dialer::OnBnClickedMuteOutput()
{
	CButton *button = (CButton*)GetDlgItem(IDC_BUTTON_MUTE_OUTPUT);
	if (button->GetCheck() == BST_CHECKED) {
		button->SetIcon(m_hIconMuteOutput);
		muteOutput = FALSE;
		OnHScroll(0, 0, NULL);
	}
	else {
		button->SetIcon(m_hIconMutedOutput);
		muteOutput = TRUE;
		OnHScroll(0, 0, NULL);
	}
	button->SetCheck(!button->GetCheck());
}

void Dialer::OnBnClickedMuteInput()
{
	CButton *button = (CButton*)GetDlgItem(IDC_BUTTON_MUTE_INPUT);
	if (button->GetCheck() == BST_CHECKED) {
		button->SetIcon(m_hIconMuteInput);
		muteInput = FALSE;
		OnHScroll(0, 0, NULL);
	}
	else {
		button->SetIcon(m_hIconMutedInput);
		muteInput = TRUE;
		OnHScroll(0, 0, NULL);
	}
	button->SetCheck(!button->GetCheck());
	if (accountSettings.headsetSupport) {
		Hid::SetMute(muteInput);
	}
}

void Dialer::TimerVuMeter()
{
	unsigned tx_level = 0, rx_level = 0;
	pjsua_conf_port_id ids[PJSUA_MAX_CONF_PORTS];
	unsigned count = PJSUA_MAX_CONF_PORTS;
	if (pjsua_var.state == PJSUA_STATE_RUNNING && pjsua_call_get_count() && pjsua_enum_conf_ports(ids, &count) == PJ_SUCCESS && count > 1) {
		for (unsigned i = 0; i < count; i++) {
			unsigned tx_level_curr, rx_level_curr;
			pjsua_conf_port_info conf_port_info;
#ifdef NDEBUG
			if (pjsua_conf_get_port_info(ids[i], &conf_port_info) == PJ_SUCCESS) {
				if (pjsua_conf_get_signal_level(ids[i], &tx_level_curr, &rx_level_curr) == PJ_SUCCESS) {
					if (conf_port_info.slot_id == 0) {
						tx_level = rx_level_curr * (conf_port_info.rx_level_adj > 0 ? 1 : 0);
					}
					else {
						rx_level_curr = conf_port_info.rx_level_adj > 0 ? rx_level_curr : 0;
						if (rx_level_curr > rx_level) {
							rx_level = rx_level_curr;
						}
					}
				}
			}
#endif
		}
		if (!m_SliderCtrlInput.IsActive) m_SliderCtrlInput.IsActive = true;
		if (!m_SliderCtrlOutput.IsActive) m_SliderCtrlOutput.IsActive = true;
	}
	else {
		KillTimer(IDT_TIMER_VU_METER);
		m_SliderCtrlInput.IsActive = false;
		m_SliderCtrlOutput.IsActive = false;
	}
	//CString s;
	//s.Format(_T("tx %d rx %d"),tx_level_max, tx_level_max);
	//mainDlg->SetWindowText(s);
	m_SliderCtrlInput.SetSelection(0, tx_level / 0.95);
	m_SliderCtrlInput.Invalidate(FALSE);
	m_SliderCtrlOutput.SetSelection(0, rx_level / 1.15);
	m_SliderCtrlOutput.Invalidate(FALSE);
}


BOOL Dialer::OnSetCursor(CWnd* pWnd, UINT nHitTest, UINT message)
{
	if (pWnd == &m_ButtonVoicemail || pWnd == &m_ButtonVoicemailDisabled) {
		::SetCursor(m_hCursorHand);
		return TRUE;
	}
	return CBaseDialog::OnSetCursor(pWnd, nHitTest, message);
}

void Dialer::OnBnClickedDND()
{
	mainDlg->SwitchDND();
}

void Dialer::OnBnClickedFWD()
{
	accountSettings.FWD = m_ButtonFWD.GetCheck() == BST_CHECKED;
	mainDlg->UpdateWindowText();
	mainDlg->AccountSettingsPendingSave();
}

void Dialer::OnBnClickedAA()
{
	accountSettings.AA = m_ButtonAA.GetCheck() == BST_CHECKED;
	mainDlg->UpdateWindowText();
	mainDlg->AccountSettingsPendingSave();
}

void Dialer::OnBnClickedAC()
{
	accountSettings.AC = m_ButtonAC.GetCheck() == BST_CHECKED;
	mainDlg->UpdateWindowText();
	mainDlg->AccountSettingsPendingSave();
}

void Dialer::OnBnClickedConf()
{
	if (accountSettings.singleMode) {
		mainDlg->OpenTransferDlg(mainDlg, MSIP_ACTION_INVITE);
	}
	else {
		mainDlg->messagesDlg->OnBnClickedConference();
	}
}

void Dialer::OnBnClickedRec()
{
	MessagesContact*  messagesContact = mainDlg->messagesDlg->GetMessageContact();
	if (messagesContact && messagesContact->callId != -1) {
		call_user_data *user_data = (call_user_data *)pjsua_call_get_user_data(messagesContact->callId);
		if (user_data) {
			user_data->CS.Lock();
			if (user_data->recorder_id == PJSUA_INVALID_ID) {
				msip_call_recording_start(user_data);
			}
			else {
				msip_call_recording_stop(user_data, 0, true);
			}
			user_data->CS.Unlock();
			mainDlg->messagesDlg->UpdateRecButton(user_data);
		}
	}
}

void Dialer::OnBnClickedVoicemail()
{
	if (accountSettings.accountId && !accountSettings.account.voicemailNumber.IsEmpty()) {
		mainDlg->MakeCall(accountSettings.account.voicemailNumber);
	}
}

void Dialer::OnBnClickedShortcut(UINT nID)
{
	if (shortcuts.GetCount() == shortcutButtons.GetCount()) {
		int i = nID - IDC_SHORTCUT_RANGE;
		mainDlg->ShortcutAction(&shortcuts.GetAt(i), false, !(((CButton*)GetDlgItem(nID))->GetCheck() & BST_CHECKED));
	}
}

void Dialer::SetCheckDND(bool checked)
{
	if (IsChild(&m_ButtonDND)) {
		m_ButtonDND.SetCheck(checked ? BST_CHECKED : BST_UNCHECKED);
	}
}
void Dialer::SetCheckREC(bool checked)
{
	if (IsChild(&m_ButtonRec)) {
		m_ButtonRec.SetCheck(checked ? BST_CHECKED : BST_UNCHECKED);
	}
}
void Dialer::EnableButtonCONF(bool enabled)
{
	if (IsChild(&m_ButtonConf)) {
		m_ButtonConf.EnableWindow(enabled);
	}
}
