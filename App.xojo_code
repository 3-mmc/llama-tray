#tag Class
Protected Class App
Inherits DesktopApplication
	#tag Event
		Sub Closing()
		  If mTray <> Nil Then
		    Self.RemoveTrayItem(mTray)
		  End If
		End Sub
	#tag EndEvent

	#tag Event
		Sub Opening()
		  ' No windows: the tray icon is the whole UI.
		  AllowAutoQuit = False
		  mRunning = New Dictionary
		  mModelNames = New Dictionary

		  mTray = New TrayIcon
		  mTray.Icon = MakeIcon(kColorIdle)
		  mTray.Tooltip = "LlamaTray: connecting to llama-swap"
		  If Not Self.AddTrayItem(mTray) Then
		    MessageBox("LlamaTray could not add its tray icon.")
		    Quit
		  End If

		  mTimer = New Timer
		  mTimer.Period = kPollMs
		  mTimer.RunMode = Timer.RunModes.Multiple
		  AddHandler mTimer.Action, WeakAddressOf Tick
		  Tick(mTimer)
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h21
		Private Sub ActionDone(sender As URLConnection, URL As String, HTTPStatus As Integer, content As String)
		  #Pragma Unused URL
		  #Pragma Unused content
		  Var what As String = ForgetAction(sender)
		  ' /upstream/<model>/ answers with whatever the model server serves at its root,
		  ' which can be a 404 even though the load itself worked, so only unloads are checked.
		  If HTTPStatus >= 400 And what <> "load" Then
		    MessageBox("llama-swap answered HTTP " + HTTPStatus.ToString + " to " + what + ".")
		  End If
		  Tick(mTimer)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ActionError(sender As URLConnection, e As RuntimeException)
		  Var what As String = ForgetAction(sender)
		  MessageBox("Request to llama-swap (" + what + ") failed: " + e.Message)
		  Tick(mTimer)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ForgetAction(c As URLConnection) As String
		  Var what As String
		  For i As Integer = mActions.LastIndex DownTo 0
		    If mActions(i) = c Then
		      what = mActionWhat(i)
		      mActions.RemoveAt(i)
		      mActionWhat.RemoveAt(i)
		    End If
		  Next
		  Return what
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub GpuCompleted(sender As Shell)
		  ' nvidia-smi --format=csv,noheader,nounits -> "1832, 8192" (MiB)
		  Var parts() As String = sender.Result.Trim.ToArray(",")
		  If parts.Count >= 2 Then
		    mVramUsed = parts(0).Trim.ToInteger
		    mVramTotal = parts(1).Trim.ToInteger
		  End If
		  Refresh
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Label(id As String) As String
		  If mModelNames.HasKey(id) Then
		    Var name As String = mModelNames.Value(id)
		    If name <> "" And name <> id Then Return name + "  (" + id + ")"
		  End If
		  Return id
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeIcon(c As Color) As Picture
		  ' A filled disc in the state colour, with a white bar whose height is VRAM use.
		  Var p As New Picture(32, 32)
		  Var g As Graphics = p.Graphics
		  g.AntiAliased = True
		  g.DrawingColor = c
		  g.FillOval(1, 1, 30, 30)
		  If mVramTotal > 0 Then
		    Var h As Integer = Round(22 * Min(1.0, mVramUsed / mVramTotal))
		    g.DrawingColor = &cFFFFFF00
		    g.DrawRectangle(12, 5, 8, 22)
		    g.FillRectangle(12, 27 - h, 8, h)
		  End If
		  Return p
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ModelsReceived(sender As URLConnection, URL As String, HTTPStatus As Integer, content As String)
		  #Pragma Unused sender
		  #Pragma Unused URL
		  If HTTPStatus <> 200 Then Return
		  ' Keep real models only; aliases (ipa, whisper, ollama tags...) would flood the menu.
		  Var ids() As String
		  Var names As New Dictionary
		  Try
		    Var d As Dictionary = ParseJSON(content)
		    Var arr() As Variant = d.Value("data")
		    For Each v As Variant In arr
		      Var m As Dictionary = v
		      Var kind As String = "model"
		      If m.HasKey("meta") Then
		        Var meta As Dictionary = m.Value("meta")
		        If meta.HasKey("llamaswap") Then
		          Var ls As Dictionary = meta.Value("llamaswap")
		          If ls.HasKey("type") Then kind = ls.Value("type").StringValue
		        End If
		      End If
		      If kind = "model" Then
		        Var id As String = m.Value("id").StringValue
		        ids.Add(id)
		        names.Value(id) = If(m.HasKey("name"), m.Value("name").StringValue, id)
		      End If
		    Next
		  Catch e As RuntimeException
		    Return
		  End Try
		  mModels = ids
		  mModelNames = names
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub OpenUI()
		  System.GotoURL(kBase + "/ui/")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub PollError(sender As URLConnection, e As RuntimeException)
		  #Pragma Unused sender
		  #Pragma Unused e
		  mReachable = False
		  mRunning = New Dictionary
		  Refresh
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Refresh()
		  Var col As Color
		  Var tip As String
		  If Not mReachable Then
		    col = kColorDown
		    tip = "llama-swap unreachable on :9292"
		  ElseIf mRunning.KeyCount = 0 Then
		    col = kColorIdle
		    tip = "Nothing loaded"
		  Else
		    Var parts() As String
		    Var settling As Boolean
		    For Each k As Variant In mRunning.Keys
		      Var st As String = mRunning.Value(k)
		      If st = "ready" Then
		        parts.Add(k.StringValue)
		      Else
		        parts.Add(k.StringValue + " (" + st + ")")
		        settling = True
		      End If
		    Next
		    col = If(settling, kColorBusy, kColorReady)
		    tip = String.FromArray(parts, ", ")
		  End If
		  If mVramTotal > 0 Then
		    tip = tip + EndOfLine + "VRAM " + Format(mVramUsed / 1024, "0.0") + " / " + Format(mVramTotal / 1024, "0.0") + " GB"
		  End If
		  ' Windows truncates tray tooltips at 127 characters.
		  If tip.Length > 120 Then tip = tip.Left(117) + "..."

		  Var key As String = tip + "|" + col.Red.ToString + "," + col.Green.ToString + "," + col.Blue.ToString
		  If key = mLastKey Then Return
		  mLastKey = key
		  mTray.Icon = MakeIcon(col)
		  mTray.Tooltip = tip
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Request(method As String, path As String, what As String)
		  Var c As New URLConnection
		  AddHandler c.ContentReceived, WeakAddressOf ActionDone
		  AddHandler c.Error, WeakAddressOf ActionError
		  ' Held in mActions so a long model load is not cancelled by garbage collection.
		  mActions.Add(c)
		  mActionWhat.Add(what)
		  c.Send(method, kBase + path, 900)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub RestartGateway()
		  Var d As New MessageDialog
		  d.Message = "Restart the llama-swap gateway?"
		  d.Explanation = "This kills every running model, including queued ComfyUI jobs."
		  d.ActionButton.Caption = "Restart"
		  d.CancelButton.Visible = True
		  If d.ShowModal <> d.ActionButton Then Return

		  If mRestartShell = Nil Then
		    mRestartShell = New Shell
		    mRestartShell.ExecuteMode = Shell.ExecuteModes.Asynchronous
		  End If
		  mRestartShell.Execute("powershell -NoProfile -ExecutionPolicy Bypass -Command ""& 'D:\llama-swap\gateway.ps1' stop; & 'D:\llama-swap\gateway.ps1' start""")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub RunningReceived(sender As URLConnection, URL As String, HTTPStatus As Integer, content As String)
		  #Pragma Unused sender
		  #Pragma Unused URL
		  mReachable = (HTTPStatus = 200)
		  Var r As New Dictionary
		  If mReachable Then
		    Try
		      Var d As Dictionary = ParseJSON(content)
		      Var arr() As Variant = d.Value("running")
		      For Each v As Variant In arr
		        Var m As Dictionary = v
		        r.Value(m.Value("model").StringValue) = m.Value("state").StringValue
		      Next
		    Catch e As RuntimeException
		    End Try
		  End If
		  mRunning = r
		  Refresh
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub ShowMenu()
		  Var m As New DesktopMenuItem

		  Var head As New DesktopMenuItem(If(mReachable, "llama-swap on :9292", "llama-swap unreachable"))
		  head.Enabled = False
		  m.AddMenu(head)
		  If mVramTotal > 0 Then
		    Var vram As New DesktopMenuItem("VRAM " + Format(mVramUsed / 1024, "0.0") + " / " + Format(mVramTotal / 1024, "0.0") + " GB")
		    vram.Enabled = False
		    m.AddMenu(vram)
		  End If
		  m.AddMenu(New DesktopMenuItem(DesktopMenuItem.TextSeparator))

		  For Each k As Variant In mRunning.Keys
		    m.AddMenu(New DesktopMenuItem("Unload " + Label(k.StringValue) + "   [" + mRunning.Value(k).StringValue + "]", "unload:" + k.StringValue))
		  Next
		  If mRunning.KeyCount > 1 Then m.AddMenu(New DesktopMenuItem("Unload all", "unloadall"))

		  Var load As New DesktopMenuItem("Load")
		  For Each id As String In mModels
		    If Not mRunning.HasKey(id) Then load.AddMenu(New DesktopMenuItem(Label(id), "load:" + id))
		  Next
		  load.Enabled = mReachable And load.Count > 0
		  m.AddMenu(load)

		  m.AddMenu(New DesktopMenuItem(DesktopMenuItem.TextSeparator))
		  m.AddMenu(New DesktopMenuItem("Open llama-swap UI", "ui"))
		  m.AddMenu(New DesktopMenuItem("Restart gateway...", "restart"))
		  m.AddMenu(New DesktopMenuItem(DesktopMenuItem.TextSeparator))
		  m.AddMenu(New DesktopMenuItem("Quit LlamaTray", "quit"))

		  Var choice As DesktopMenuItem = m.PopUp
		  If choice = Nil Or choice.Tag = Nil Then Return
		  Var tag As String = choice.Tag.StringValue

		  If tag.BeginsWith("unload:") Then
		    Request("POST", "/api/models/unload/" + tag.Middle(7), "unload")
		  ElseIf tag = "unloadall" Then
		    Request("POST", "/api/models/unload", "unload all")
		  ElseIf tag.BeginsWith("load:") Then
		    ' llama-swap has no load endpoint; any request through /upstream/<model>/ starts it.
		    Request("GET", "/upstream/" + tag.Middle(5) + "/", "load")
		  ElseIf tag = "ui" Then
		    OpenUI
		  ElseIf tag = "restart" Then
		    RestartGateway
		  ElseIf tag = "quit" Then
		    Quit
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Tick(sender As Timer)
		  #Pragma Unused sender
		  mPolls = mPolls + 1

		  mRunningConn = New URLConnection
		  AddHandler mRunningConn.ContentReceived, WeakAddressOf RunningReceived
		  AddHandler mRunningConn.Error, WeakAddressOf PollError
		  mRunningConn.Send("GET", kBase + "/running", 3)

		  ' The model list rarely changes (config edits), so refresh it every ~30 s.
		  If mModels.Count = 0 Or mPolls Mod 10 = 1 Then
		    mModelsConn = New URLConnection
		    AddHandler mModelsConn.ContentReceived, WeakAddressOf ModelsReceived
		    mModelsConn.Send("GET", kBase + "/v1/models", 5)
		  End If

		  If mGpuShell = Nil Then
		    mGpuShell = New Shell
		    mGpuShell.ExecuteMode = Shell.ExecuteModes.Asynchronous
		    AddHandler mGpuShell.Completed, WeakAddressOf GpuCompleted
		  End If
		  If Not mGpuShell.IsRunning Then
		    mGpuShell.Execute("nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits")
		  End If
		End Sub
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mActions() As URLConnection
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mActionWhat() As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mGpuShell As Shell
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLastKey As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mModelNames As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mModels() As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mModelsConn As URLConnection
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPolls As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mReachable As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRestartShell As Shell
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRunning As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRunningConn As URLConnection
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mTimer As Timer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mTray As TrayIcon
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mVramTotal As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mVramUsed As Integer
	#tag EndProperty


	#tag Constant, Name = kBase, Type = String, Dynamic = False, Default = \"http://127.0.0.1:9292", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kColorBusy, Type = Color, Dynamic = False, Default = \"&cE67E22", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kColorDown, Type = Color, Dynamic = False, Default = \"&cC0392B", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kColorIdle, Type = Color, Dynamic = False, Default = \"&c7F8C8D", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kColorReady, Type = Color, Dynamic = False, Default = \"&c27AE60", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEditClear, Type = String, Dynamic = False, Default = \"&Delete", Scope = Public
		#Tag Instance, Platform = Windows, Language = Default, Definition  = \"&Delete"
		#Tag Instance, Platform = Linux, Language = Default, Definition  = \"&Delete"
	#tag EndConstant

	#tag Constant, Name = kFileQuit, Type = String, Dynamic = False, Default = \"&Quit", Scope = Public
		#Tag Instance, Platform = Windows, Language = Default, Definition  = \"E&xit"
	#tag EndConstant

	#tag Constant, Name = kFileQuitShortcut, Type = String, Dynamic = False, Default = \"", Scope = Public
		#Tag Instance, Platform = Mac OS, Language = Default, Definition  = \"Cmd+Q"
		#Tag Instance, Platform = Linux, Language = Default, Definition  = \"Ctrl+Q"
	#tag EndConstant

	#tag Constant, Name = kPollMs, Type = Double, Dynamic = False, Default = \"3000", Scope = Private
	#tag EndConstant


End Class
#tag EndClass
