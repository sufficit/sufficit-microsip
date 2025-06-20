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

// microsip.cpp : Defines the class behaviors for the application.
//
#include "stdafx.h"
#include "microsip.h"
#include "mainDlg.h"
#include "const.h"
#include "settings.h"
#include "langpack.h"

#include "Strsafe.h"

#include <afxinet.h>
#include <Psapi.h>
#include <Dbghelp.h>

#pragma comment(lib, "Psapi")
#pragma comment(lib, "Dbghelp")

#ifdef _DEBUG
#define new DEBUG_NEW
#endif


// CmicrosipApp

BEGIN_MESSAGE_MAP(CmicrosipApp, CWinAppEx)
	ON_COMMAND(ID_HELP, &CWinAppEx::OnHelp)
END_MESSAGE_MAP()

void RecursiveDelete(CString path)
{
	if (!path.IsEmpty()) {
		CFileFind ff;
		if (path.Right(1) == _T("\\")) {
			path = path.Mid(0, path.GetLength() - 1);
		}
		BOOL res = ff.FindFile(path);
		while (res) {
			res = ff.FindNextFile();
			if (!ff.IsDots()) {
				if (ff.IsDirectory()) {
					path = ff.GetFilePath();
					CString path1 = path;
					path1.Append(_T("\\*.*"));
					RecursiveDelete(path1);
					RemoveDirectory(path);
				}
				else {
					DeleteFile(ff.GetFilePath());
				}
			}
		}
	}
}

// CmicrosipApp construction

CmicrosipApp::CmicrosipApp()
{
	// TODO: add construction code here,
	// Place all significant initialization in InitInstance
}


// The one and only CmicrosipApp object

CmicrosipApp theApp;

// CmicrosipApp initialization

CStringA wineVersion() {
	static const char * (CDECL *pwine_get_version)(void);
	HMODULE hntdll = GetModuleHandle(_T("ntdll.dll"));
	if (hntdll) {
		pwine_get_version = (const char* (*)())(void *)GetProcAddress(hntdll, "wine_get_version");
		if (pwine_get_version) {
			return pwine_get_version();
		}
	}
	return "n/a";
}

LONG WINAPI ExceptionFilter(EXCEPTION_POINTERS *ExceptionInfo)
{
	CTime tm = CTime::GetCurrentTime();
	bool sent = false;
	CString blockFileName = accountSettings.pathLocal;
	blockFileName.AppendFormat(_T("block_%d.%d.%d.%d.dat"), _GLOBAL_VERSION_COMMA);
	bool blockDump = PathFileExists(blockFileName);
	if (!blockDump) {
		CString filename;
		CFile file;
		// mini dump
		filename.Format(_T("%sdump%s.dmp"), accountSettings.pathLocal, tm.Format(_T("_%Y-%m-%d_%H-%M-%S")));
		if (file.Open(filename, CFile::modeCreate | CFile::modeReadWrite)) {
			MINIDUMP_EXCEPTION_INFORMATION MinidumpExceptionInfo;
			MinidumpExceptionInfo.ThreadId = GetCurrentThreadId();
			MinidumpExceptionInfo.ExceptionPointers = ExceptionInfo;
			MinidumpExceptionInfo.ClientPointers = FALSE;
			if (MiniDumpWriteDump(
				GetCurrentProcess(),
				GetCurrentProcessId(),
				file.m_hFile,
				MiniDumpNormal,
				&MinidumpExceptionInfo,
				NULL,
				NULL
			)) {
			}
			file.Close();
		}
	}
	if (pj_ready && pjsua_var.state == PJSUA_STATE_RUNNING && tm.GetTime() - startTime.GetTime() > 10) {
		// automatic restart after sip crash
		ShellExecute(NULL, NULL, accountSettings.exeFile, NULL, NULL, SW_SHOWDEFAULT);
		return EXCEPTION_EXECUTE_HANDLER;
	}
	else {
		CString message;
		if (blockDump) {
			CString caption;
			caption.Format(_T("%s %s"), _T(_GLOBAL_NAME_NICE), Translate(_T("Update Available")));
			message.Format(_T("%s %s"),
				Translate(_T("The current version is unstable on your system. You should update to the latest version.")),
				Translate(_T("Do you want to update now?"))
			);
			if (::MessageBox(NULL, message, caption, MB_YESNO | MB_ICONQUESTION) == IDYES) {
				MSIP::OpenURL(_T("https://www.microsip.org/downloads"));
			}
		}
		else {
#ifdef _GLOBAL_VIDEO
			message.Format(_T("A crash happened. Check your video card drivers or update DirectX. Try to install the LITE version (without video). Tracking info: %s%s"), tm.Format(_T("%Y%m%d%H%M%S")), sent ? _T("Y") : _T("N"));
#else
			message.Format(_T("A crash happened. Make sure your system is healthy and you have enough free memory and hard disk space. You can try to uninstall Microsip \"with configuration\", and install it again. If this is a softphone bug, you can contact us to help fix it. Tracking info: %s%s"), tm.Format(_T("%Y%m%d%H%M%S")), sent ? _T("Y") : _T("N"));
#endif
			AfxMessageBox(message, MB_ICONERROR);
		}
		return EXCEPTION_EXECUTE_HANDLER;
	}
	return EXCEPTION_CONTINUE_SEARCH;
}

struct MsipEnumWindowsProcData {
	HINSTANCE hInst;
	HWND hWnd;
	int count;
};

BOOL CALLBACK MsipEnumWindowsProc(HWND hWnd, LPARAM lParam)
{
	MsipEnumWindowsProcData *data = (MsipEnumWindowsProcData *)lParam;
	HINSTANCE hInstance = (HINSTANCE)GetWindowLongPtr(hWnd, GWLP_HINSTANCE);
	if (hInstance && hInstance == data->hInst && GetWindow(hWnd, GW_OWNER) == (HWND)0) {
		TCHAR className[256];
		if (GetClassName(hWnd, className, 256)) {
			if (StrCmp(className, _T(_GLOBAL_NAME)) == 0) {
				//--
				DWORD dwProcessID;
				GetWindowThreadProcessId(hWnd, &dwProcessID);
				HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION |
					PROCESS_VM_READ, FALSE, dwProcessID);
				if (hProcess) {
					TCHAR exeFilePath[MAX_PATH];
					if (GetModuleFileNameEx(hProcess, NULL, exeFilePath, MAX_PATH)) {
						if (StrCmpI (exeFilePath, accountSettings.exeFile) == 0) {
							data->hWnd = hWnd;
							data->count++;
							return FALSE;
						}
					}
					CloseHandle(hProcess);
				}
				//--
			}
		}
	}
	return TRUE;
}

BOOL CmicrosipApp::InitInstance()
{
	accountSettings.Init();

	SetUnhandledExceptionFilter(ExceptionFilter);
	MsipEnumWindowsProcData data;
	data.hInst = AfxGetInstanceHandle();
	data.count = 0;
	HWND hWndRunning = NULL;

	EnumWindows(MsipEnumWindowsProc, (LPARAM)&data);
	if (data.count) {
		hWndRunning = data.hWnd;
	}

	//*((char*)NULL) = 0; //produce a crash!!

	bool cmdReset = lstrcmp(theApp.m_lpCmdLine, _T("/reset")) == 0;
	bool cmdResetNoAsk = lstrcmp(theApp.m_lpCmdLine, _T("/resetnoask")) == 0;
	if (cmdReset || cmdResetNoAsk) {
		if (hWndRunning) {
			::SendMessage(hWndRunning, WM_CLOSE, NULL, NULL);
		}
		if (cmdResetNoAsk || AfxMessageBox(Translate(_T("Do you want to delete user data and program settings? This action cannot be undone.")), MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | MB_SYSTEMMODAL) == IDYES) {
			if (cmdResetNoAsk || AfxMessageBox(Translate(_T("Are you sure you want to delete?")), MB_YESNO | MB_ICONQUESTION | MB_SYSTEMMODAL) == IDYES) {
				RecursiveDelete(accountSettings.appDataRoaming);
				if (!::PathFileExists(accountSettings.appDataLocal + _T("Uninstall.exe"))) {
					RecursiveDelete(accountSettings.appDataLocal);
				}
			}
		}
		return FALSE;
	}
	bool cmdExit = lstrcmp(theApp.m_lpCmdLine, _T("/exit")) == 0;
	if (cmdExit) {
		if (hWndRunning) {
			::SendMessage(hWndRunning, WM_CLOSE, NULL, NULL);
		}
		return FALSE;
	}
	if (hWndRunning) {
		if ( lstrcmp(theApp.m_lpCmdLine, _T("/minimized"))==0) {
		} else if ( lstrcmp(theApp.m_lpCmdLine, _T("/hidden"))==0) {
		} else {
			bool activate = true;
			if (lstrlen(theApp.m_lpCmdLine)) {
				COPYDATASTRUCT cd;
				cd.dwData = 1;
				cd.lpData = theApp.m_lpCmdLine;
				cd.cbData = sizeof(TCHAR) * (lstrlen(theApp.m_lpCmdLine) + 1);
				activate = ::SendMessage(hWndRunning, WM_COPYDATA, NULL, (LPARAM)&cd);
			}
			if (activate && !MACRO_SILENT) {
				::ShowWindow(hWndRunning, SW_SHOW);
				::SetForegroundWindow(hWndRunning);
			}
		}
		return FALSE;
	} else {
		if (lstrcmp(theApp.m_lpCmdLine, _T("/answer")) == 0
			|| lstrcmp(theApp.m_lpCmdLine, _T("/hangupall")) == 0
			) {
			return FALSE;
		}
	}

	// InitCommonControlsEx() is required on Windows XP if an application
	// manifest specifies use of ComCtl32.dll version 6 or later to enable
	// visual styles.  Otherwise, any window creation will fail.
	// Set this to include all the common control classes you want to use
	// in your application.
	INITCOMMONCONTROLSEX InitCtrls;
	InitCtrls.dwSize = sizeof(InitCtrls);
	InitCtrls.dwICC = ICC_LISTVIEW_CLASSES |
		ICC_LINK_CLASS | 
		ICC_BAR_CLASSES | 
		ICC_LINK_CLASS | 
		ICC_STANDARD_CLASSES | 
		ICC_TAB_CLASSES | 
		ICC_UPDOWN_CLASS;

	InitCommonControlsEx(&InitCtrls);

	// Initialize OLE libraries (need this for Virtual Display)
	if (!AfxOleInit())
	{
		AfxMessageBox(_T("OLE initialization failed.  Make sure that the OLE libraries are the correct version."));
		return FALSE;
	}

	AfxEnableControlContainer();

	// disabled, conflict with AfxOleInit
	//if (CoInitializeEx(NULL, COINIT_MULTITHREADED) != S_OK)
	//{
	//	AfxMessageBox(_T("COM initialization failed."));
	//	return FALSE;
	//}

	AfxInitRichEdit2();

	InitShellManager();

	WNDCLASS wc;
	// Get the info for this class.
    // #32770 is the default class name for dialogs boxes.
	::GetClassInfo(AfxGetInstanceHandle(), L"#32770", &wc);
	wc.lpszClassName = _T(_GLOBAL_NAME);
	// Register this class so that MFC can use it.
	if (!::AfxRegisterClass(&wc)) return FALSE;

	CmainDlg *mainDlg = new CmainDlg;
	m_pMainWnd = mainDlg;

	if (!m_pMainWnd) {
		// return FALSE so that we exit the
		// application, rather than start the application's message pump.
		return FALSE;
	}

	if (!mainDlg->GetDlgItem(IDC_MAIN_TAB)) {
		DWORD error = GetLastError();
		CString message;
		message.Format(_T("Window creation failed. Error %d"), error);
		AfxMessageBox(message, MB_ICONERROR);
		return FALSE;
	}

	//--

	mainDlg->OnCreated();

	//--

	return TRUE;

}
