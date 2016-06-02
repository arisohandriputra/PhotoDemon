VERSION 5.00
Begin VB.UserControl pdDropDownFont 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   390
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   5610
   ClipControls    =   0   'False
   DrawStyle       =   5  'Transparent
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   9.75
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   ScaleHeight     =   26
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   374
   ToolboxBitmap   =   "pdDropDownFont.ctx":0000
   Begin PhotoDemon.pdListBoxOD lbPrimary 
      Height          =   375
      Left            =   0
      TabIndex        =   0
      Top             =   0
      Visible         =   0   'False
      Width           =   4935
      _ExtentX        =   2566
      _ExtentY        =   661
   End
End
Attribute VB_Name = "pdDropDownFont"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Font-specific Drop Down control 2.0
'Copyright 2016-2016 by Tanner Helland
'Created: 01/June/16
'Last updated: 01/June/16
'Last update: based updated version of the control off the new listbox, instead of trying to integrate with a system
'             combo box (an approach that had all sorts of horrific problems)
'
'This is a basic dropdown control, with no edit box functionality (by design).  It is very similar in construction to
' the pdListBoxOD object, including its reliance on a separate pdListSupport class for managing its data.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This control raises much fewer events than a standard ListBox, by design
Public Event Click()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'Positioning the dynamically raised listview window is a bit hairy; we use APIs so we can position things correctly
' in the screen's coordinate space (even on high-DPI displays)
Private Declare Function GetWindowRect Lib "user32" (ByVal srcHwnd As Long, ByRef dstRectL As RECTL) As Boolean
Private Declare Function GetParent Lib "user32" (ByVal targetHwnd As Long) As Long
Private Declare Function SetParent Lib "user32" (ByVal hWndChild As Long, ByVal hWndNewParent As Long) As Long
Private Declare Function GetWindowLong Lib "user32" Alias "GetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long) As Long
Private Declare Function SetWindowLong Lib "user32" Alias "SetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) As Long
Private Const GWL_EXSTYLE As Long = -20
Private Const WS_EX_TOOLWINDOW As Long = &H80&
Private m_WindowStyleHasBeenSet As Boolean

Private Declare Sub SetWindowPos Lib "user32" (ByVal targetHwnd As Long, ByVal hWndInsertAfter As Long, ByVal x As Long, ByVal y As Long, ByVal cx As Long, ByVal cy As Long, ByVal wFlags As Long)
Private Const SWP_SHOWWINDOW As Long = &H40
Private Const SWP_NOACTIVATE As Long = &H10

'When the popup listbox is raised, we subclass the parent control.  If it is moved or sized or clicked, we automatically
' unload the dropdown listview.  (This workaround is necessary for modal dialogs, among other things.)
Private m_Subclass As cSelfSubHookCallback
Private m_ParentHWnd As Long
Private Const WM_ENTERSIZEMOVE As Long = &H231
Private Const WM_LBUTTONDOWN As Long = &H201
Private Const WM_RBUTTONDOWN As Long = &H204
Private Const WM_MBUTTONDOWN As Long = &H207
Private Const WM_WINDOWPOSCHANGING As Long = &H46&

'Font size of the dropdown (and corresponding listview).  This controls all rendering metrics, so please don't change
' it at run-time.  Also, note that the optional caption fontsize is a totally different property that can (and should)
' be set independently.
Private m_FontSize As Single

'In a normal dropdown, we can use the same metrics for both the list and the box itself.  For a font box, however,
' the list entries must be taller than the dropdown area.  As such, we let the (more intelligent) list manager handle
' the list box metrics, while we manually control the dropdown box's height.
Private m_IdealComboBoxHeight As Single

'The font drop-down box is unique in that its list area is deliberately wider than the dropdown area (which tends to
' be quite small, on account of the tool options area being snug).  When the font size of the control changes,
' we find the longest font name, and use that as the basis for our list box width.
Private m_LargestWidth As Single

'Padding around the currently selected list item when painted to the combo box.  These values are also added to the
' default font metrics to arrive at a default control size.
Private Const COMBO_PADDING_HORIZONTAL As Single = 4#
Private Const COMBO_PADDING_VERTICAL As Single = 2#

'Change this value to control the maximum number of visible items in the dropped box.  (Note that it's technically
' this value + 1, with the +1 representing the currently selected item.)
Private Const NUM_ITEMS_VISIBLE As Long = 10

'The rectangle where the combo portion of the control is actually rendered
Private m_ComboRect As RECTF, m_MouseInComboRect As Boolean

'When the control receives focus via keyboard (e.g. NOT by mouse events), we draw a focus rect to help orient the user.
Private m_FocusRectActive As Boolean

'When the popup listbox is visible, this is set to TRUE.  (Also, as a failsafe the list box hWnd is cached.)
Private m_PopUpVisible As Boolean, m_PopUpHwnd As Long

'Current background color; (background color is used for the 1px border around the button, and it should always match
' our parent control).
Private m_UseCustomBackgroundColor As Boolean, m_BackgroundColor As OLE_COLOR

'List box support class.  Handles data storage and coordinate math for rendering, but for this control, we primarily
' use the data storage aspect.  (Note that when the combo box is clicked and the corresponding listbox window is raised,
' we hand a copy of this class over to the list view so it can clone it and mirror our data.)
Private WithEvents listSupport As pdListSupport
Attribute listSupport.VB_VarHelpID = -1

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'If something forces us to release our subclass while in the midst of the subclass proc, we want to delay the request until
' the subclass exits.  If we don't do this, PD will crash.
Private m_InSubclassNow As Boolean, m_SubclassActive As Boolean
Private WithEvents m_SubclassReleaseTimer As pdTimer
Attribute m_SubclassReleaseTimer.VB_VarHelpID = -1

'String stack that mirrors the current program font cache.
Private m_listOfFonts As pdStringStack

'This UC will be generating an enormous amount of fonts.  We attempt to alleviate this burden by maintaining a persistent collection of the
' past N fonts we've created, on the assumption that we can reuse them at least a few times as the user scrolls the dropdown.
Private m_FontCollection As pdFontCollection

'Preview string to demo each font face.  This is arbitrary, and currently set during the Initialize event.
' (Adding additional scripts is on the TODO list!)
Private m_Text_Default As String
Private m_Text_EN As String
Private m_Text_CJK As String
Private m_Text_Arabic As String
Private m_Text_Hebrew As String

'Because the listbox portion fo this control is owner-drawn, we must perform our own item height measurements.  These are
' calculated against a test string when creating the list; the result is stored to this variable.
Private m_ItemHeight As Long

'DrawText functions
Private Declare Function SelectObject Lib "gdi32" (ByVal hDC As Long, ByVal hObject As Long) As Long
Private Declare Function DeleteObject Lib "gdi32" (ByVal hObject As Long) As Long
Private Declare Function DrawText Lib "user32" Alias "DrawTextW" (ByVal hDC As Long, ByVal lpStr As Long, ByVal nCount As Long, ByRef lpRect As RECT, ByVal wFormat As Long) As Long

'GDI text alignment flags
Private Const TA_LEFT = 0
Private Const TA_RIGHT = 2
Private Const TA_CENTER = 6
Private Const TA_TOP = 0
Private Const TA_BOTTOM = 8
Private Const TA_BASELINE = 24
Private Const TA_UPDATECP = 1
Private Const TA_NOUPDATECP = 0

'Back color modes (not useful here except during debug mode)
Private Const FONT_TRANSPARENT = &H1
Private Const FONT_OPAQUE = &H2

'Formatting constants for DrawText
Private Const DT_TOP = &H0
Private Const DT_LEFT = &H0
Private Const DT_CENTER = &H1
Private Const DT_RIGHT = &H2
Private Const DT_VCENTER = &H4
Private Const DT_BOTTOM = &H8
Private Const DT_WORDBREAK = &H10
Private Const DT_SINGLELINE = &H20
Private Const DT_EXPANDTABS = &H40
Private Const DT_TABSTOP = &H80
Private Const DT_NOCLIP = &H100
Private Const DT_EXTERNALLEADING = &H200
Private Const DT_CALCRECT = &H400
Private Const DT_NOPREFIX = &H800
Private Const DT_INTERNAL = &H1000
Private Const DT_EDITCONTROL = &H2000
Private Const DT_PATH_ELLIPSIS = &H4000
Private Const DT_END_ELLIPSIS = &H8000
Private Const DT_MODIFYSTRING = &H10000
Private Const DT_RTLREADING = &H20000
Private Const DT_WORD_ELLIPSIS = &H40000


'Local list of themable colors.  This list includes all potential colors used by this class, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDDROPDOWNFONT_COLOR_LIST
    [_First] = 0
    PDDD_Background = 0
    PDDD_ComboFill = 1
    PDDD_ComboBorder = 2
    PDDD_DropDownCaption = 3
    PDDD_DropArrow = 4
    PDDD_ListCaption = 5
    PDDD_ListBorder = 6
    [_Last] = 6
    [_Count] = 7
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

'Initialize the combo box.  This must be called once, by the caller, prior to display.  The combo box will internally cache its
' own copy of the font list, and if for some reason the list changes, this function can be called again to reset the font list.
Public Sub InitializeFontList()
    Me.Clear
    Font_Management.GetCopyOfSystemFontList m_listOfFonts
    CopyFontsToListManager
End Sub

'Duplicate a given string inside the API combo box.  We don't actually use this copy of the string (we use our own, so we can support Unicode),
' but this provides a fallback for accessibility technology.
Private Sub CopyFontsToListManager()

    listSupport.SetAutomaticRedraws False
        
    'Iterate through the string stack, adding fonts as we go
    Dim i As Long
    For i = 0 To m_listOfFonts.GetNumOfStrings - 1
        listSupport.AddItem m_listOfFonts.GetString(i), i
    Next i
    
    listSupport.SetAutomaticRedraws True
    
End Sub

'BackgroundColor and BackColor are different properties.  BackgroundColor should always match the color of the parent control,
' while BackColor controls the actual button fill (and can be anything you want).
Public Property Get BackgroundColor() As OLE_COLOR
    BackgroundColor = m_BackgroundColor
End Property

Public Property Let BackgroundColor(ByVal newColor As OLE_COLOR)
    If m_BackgroundColor <> newColor Then
        m_BackgroundColor = newColor
        RedrawBackBuffer
    End If
End Property

Public Property Get UseCustomBackgroundColor() As Boolean
    UseCustomBackgroundColor = m_UseCustomBackgroundColor
End Property

Public Property Let UseCustomBackgroundColor(ByVal newSetting As Boolean)
    If (newSetting <> m_UseCustomBackgroundColor) Then
        m_UseCustomBackgroundColor = newSetting
        RedrawBackBuffer
    End If
End Property

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if it ever becomes relevant.
Public Property Get Caption() As String
    Caption = ucSupport.GetCaptionText()
End Property

Public Property Let Caption(ByRef newCaption As String)
    ucSupport.SetCaptionText newCaption
    PropertyChanged "Caption"
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    UserControl.Enabled = newValue
    RedrawBackBuffer
    PropertyChanged "Enabled"
End Property

'Font settings other than size are not supported.  If you want specialized per-item rendering, use an owner-drawn list box
Public Property Get FontSize() As Single
    FontSize = m_FontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    
    m_FontSize = newSize
    
    'A *ton* of rendering metrics are tied to the current font size.  All must be refreshed upon a change.
    m_LargestWidth = 0
    m_IdealComboBoxHeight = Font_Management.GetDefaultStringHeight(m_FontSize) + COMBO_PADDING_VERTICAL * 2
    lbPrimary.ListItemHeight = Font_Management.GetDefaultStringHeight(m_FontSize) * 2 + 2
    listSupport.DefaultItemHeight = lbPrimary.ListItemHeight
    
    PropertyChanged "FontSize"
    
End Property

'Font settings other than size are not supported.  If you want specialized per-item rendering, use an owner-drawn list box
Public Property Get FontSizeCaption() As Single
    FontSizeCaption = ucSupport.GetCaptionFontSize()
End Property

Public Property Let FontSizeCaption(ByVal newSize As Single)
    ucSupport.SetCaptionFontSize newSize
    PropertyChanged "FontSizeCaption"
End Property

Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

Public Property Get hWnd() As Long
    hWnd = UserControl.hWnd
End Property

'To support high-DPI settings properly, we expose some specialized move+size functions
Public Function GetLeft() As Long
    GetLeft = ucSupport.GetControlLeft
End Function

Public Sub SetLeft(ByVal newLeft As Long)
    ucSupport.RequestNewPosition newLeft, , True
End Sub

Public Function GetTop() As Long
    GetTop = ucSupport.GetControlTop
End Function

Public Sub SetTop(ByVal newTop As Long)
    ucSupport.RequestNewPosition , newTop, True
End Sub

Public Function GetWidth() As Long
    GetWidth = ucSupport.GetControlWidth
End Function

Public Sub SetWidth(ByVal newWidth As Long)
    ucSupport.RequestNewSize newWidth, , True
End Sub

'Use this helper function to automatically set the dropdown control's width, according to the width of its longest text entry.
Public Sub SetWidthAutomatically()

    Dim newWidth As Long, testWidth As Long
    newWidth = 0
    
    If (listSupport.ListCount > 0) Then
    
        Dim i As Long
        For i = 0 To listSupport.ListCount - 1
            testWidth = Font_Management.GetDefaultStringWidth(listSupport.List(i, True), m_FontSize)
            If (testWidth > newWidth) Then newWidth = testWidth
        Next i
    
    Else
        newWidth = FixDPI(100)
    End If
    
    'The drop-down arrow's size is fixed, and we also add in the width of the scrollbar (which may be relevant for
    ' some lists)
    newWidth = newWidth + FixDPI(36)
    ucSupport.RequestNewSize newWidth, , True
    
End Sub

Public Function GetHeight() As Long
    GetHeight = ucSupport.GetControlHeight
End Function

Public Sub SetHeight(ByVal newHeight As Long)
    ucSupport.RequestNewSize , newHeight, True
End Sub

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

'Listbox-specific functions and subs.  Most of these simply relay the request to the listSupport object, and it will
' raise redraw requests as relevant.
Public Sub AddItem(Optional ByVal srcItemText As String = vbNullString, Optional ByVal itemIndex As Long = -1, Optional ByVal hasTrailingSeparator As Boolean = False, Optional ByVal itemHeight As Long = -1)
    listSupport.AddItem srcItemText, itemIndex, hasTrailingSeparator, itemHeight
End Sub

Public Sub Clear()
    listSupport.Clear
    Set m_listOfFonts = New pdStringStack
End Sub

Public Function GetDefaultItemHeight() As Long
    GetDefaultItemHeight = listSupport.DefaultItemHeight
End Function

Public Function List(ByVal itemIndex As Long, Optional ByVal returnTranslatedText As Boolean = False) As String
    List = listSupport.List(itemIndex, returnTranslatedText)
End Function

Public Function ListCount() As Long
    ListCount = listSupport.ListCount
End Function

Public Property Get ListIndex() As Long
    ListIndex = listSupport.ListIndex
End Property

Public Property Let ListIndex(ByVal newIndex As Long)
    listSupport.ListIndex = newIndex
End Property

Public Function ListIndexByString(ByRef srcString As String, Optional ByVal compareMode As VbCompareMethod = vbBinaryCompare) As Long
    ListIndexByString = listSupport.ListIndexByString(srcString, compareMode)
End Function

Public Sub RemoveItem(ByVal itemIndex As Long)
    listSupport.RemoveItem itemIndex
End Sub

Private Sub lbPrimary_Click()
    
    'Mirror any changes to the base dropdown control, then hide the list box
    Me.ListIndex = lbPrimary.ListIndex
    HideListBox
    
    'Restore the focus to the base combo box
    g_WindowManager.SetFocusAPI Me.hWnd
    
End Sub

Private Sub lbPrimary_DrawListEntry(ByVal bufferDC As Long, ByVal itemIndex As Long, itemTextEn As String, ByVal itemIsSelected As Boolean, ByVal itemIsHovered As Boolean, ByVal ptrToRectF As Long)
    
    'Cache colors in advance, so we can simply reuse them in the inner loop
    Dim itemFillColor As Long, itemFillBorderColor As Long, itemFontColor As Long
    itemFillColor = m_Colors.RetrieveColor(PDDD_ComboFill, Me.Enabled, itemIsSelected, itemIsHovered)
    itemFillBorderColor = m_Colors.RetrieveColor(PDDD_ListBorder, Me.Enabled, itemIsSelected, itemIsHovered)
    itemFontColor = m_Colors.RetrieveColor(PDDD_ListCaption, Me.Enabled, itemIsSelected, itemIsHovered)
    
    'Grab the rendering rect
    Dim tmpRectF As RECTF
    CopyMemory ByVal VarPtr(tmpRectF), ByVal ptrToRectF, 16&
    
    'Paint the fill and border
    GDI_Plus.GDIPlusFillRectFToDC bufferDC, tmpRectF, itemFillColor
    GDI_Plus.GDIPlusDrawRectFOutlineToDC bufferDC, tmpRectF, itemFillBorderColor, , , , GP_LJ_Miter
    
    'Paint the font name in the default UI font
    Dim tmpFont As pdFont, textPadding As Single
    Set tmpFont = Font_Management.GetMatchingUIFont(m_FontSize)
    textPadding = COMBO_PADDING_HORIZONTAL
    
    Dim tmpString As String
    tmpString = m_listOfFonts.GetString(itemIndex)
    
    tmpFont.SetFontColor itemFontColor
    tmpFont.AttachToDC bufferDC
    tmpFont.SetTextAlignment vbLeftJustify
    tmpFont.FastRenderTextWithClipping tmpRectF.Left + textPadding, tmpRectF.Top + COMBO_PADDING_VERTICAL, tmpRectF.Width - COMBO_PADDING_HORIZONTAL, tmpRectF.Height - COMBO_PADDING_VERTICAL, tmpString, False, True, False
    tmpFont.ReleaseFromDC
    
    'Next, we want to draw a font preview.  Instead of using a pdFont object, we handle this manually, as there are unique layout needs
    ' depending on the associated font.
    
    'Start by creating this font, as necessary
    Dim fontIndex As Long
    fontIndex = m_FontCollection.AddFontToCache(tmpString, m_FontSize + 4)

    'Retrieve a handle to the created font
    Dim fontHandle As Long
    fontHandle = m_FontCollection.GetFontHandleByPosition(fontIndex)
    
    'Select the font into the target DC
    Dim oldFont As Long
    oldFont = SelectObject(bufferDC, fontHandle)
    
    'Start by retrieving the width of the font name.  We know that this will be less than 1/2 the total width of the rect,
    ' because we created the rect size using the drawn length of the longest font name!
    Dim fontNameWidth As Long
    Dim tmpRectMeasure As RECT
    tmpFont.DrawTextWrapper StrPtr(tmpString), Len(tmpString), tmpRectMeasure, DT_LEFT Or DT_VCENTER Or DT_SINGLELINE Or DT_NOPREFIX Or DT_CALCRECT
    fontNameWidth = (tmpRectMeasure.Right - tmpRectMeasure.Left)
    
    'Generate a destination rect, inside which we will right-align the text.
    Dim previewRect As RECT
    With previewRect
        
        'For the left boundary, we use the larger of...
        ' 1) the length of the font name (as drawn in the UI font), plus a few extra pixels for padding
        ' 2) the halfway point in the drop-down area
        Dim calcLeft As Long, calcLeftAlternate As Long
        calcLeft = tmpRectF.Left + 4 + fontNameWidth + FixDPI(32)
        calcLeftAlternate = tmpRectF.Left + 4 + ((tmpRectF.Left + tmpRectF.Width) - tmpRectF.Left - 8) \ 2
        
        If calcLeft > calcLeftAlternate Then
            .Left = calcLeftAlternate
        Else
            .Left = calcLeft
        End If
        
        'Right/top/bottom are all self-explanatory
        .Right = tmpRectF.Left + tmpRectF.Width - COMBO_PADDING_HORIZONTAL
        .Top = tmpRectF.Top
        .Bottom = tmpRectF.Top + tmpRectF.Height
    End With
    
    'Create sample text based on the scripts supported by this font.  If no special scripts are supported,
    ' default English text is used.
    '
    'Note that this behavior can be overridden by the "Interface" performance property
    Dim sampleText As String
    If (g_InterfacePerformance <> PD_PERF_FASTEST) Then
    
        Dim tmpProperties As PD_FONT_PROPERTY
        If m_FontCollection.GetFontPropertiesByPosition(fontIndex, tmpProperties) Then
        
            If tmpProperties.Supports_CJK Then
                sampleText = m_Text_Default & " " & m_Text_CJK
            ElseIf tmpProperties.Supports_Arabic Then
                sampleText = m_Text_Default & " " & m_Text_Arabic
            ElseIf tmpProperties.Supports_Hebrew Then
                sampleText = m_Text_Default & " " & m_Text_Hebrew
            ElseIf tmpProperties.Supports_Latin Then
                sampleText = m_Text_Default & " " & m_Text_EN
            Else
                sampleText = m_Text_Default
            End If
            
        Else
            sampleText = m_Text_Default
        End If
        
    Else
        sampleText = m_Text_Default
    End If
    
    'Render right-aligned preview text
    If (Len(sampleText) <> 0) Then DrawText bufferDC, StrPtr(sampleText), Len(sampleText), previewRect, DT_RIGHT Or DT_VCENTER Or DT_SINGLELINE Or DT_NOPREFIX
    
    'Release our font
    SelectObject bufferDC, oldFont
                        
End Sub

Private Sub listSupport_Click()
    RaiseEvent Click
End Sub

'When the list manager detects that an action requires the list to be redrawn (like adding a new item), it will raise
' this event.  Whether or not we respond depends on several factors, like whether the user control is currently visible,
' or whether the update actually changed the ListIndex (which is the only thing this front-facing portion of the
' dropdown cares about).
Private Sub listSupport_RedrawNeeded()
    If ucSupport.AmIVisible Then RedrawBackBuffer True
End Sub

'If a subclassis active, this timer will repeatedly try to kill it.  Do not enable it until you are certain the subclass
' needs to be released.  (This is used as a failsafe if we cannot immediately release the subclass when focus is lost.)
Private Sub m_SubclassReleaseTimer_Timer()
    If (Not m_InSubclassNow) Then
        m_SubclassReleaseTimer.StopTimer
        RemoveSubclass
    End If
End Sub

Private Sub ucSupport_GotFocusAPI()
    m_FocusRectActive = True
    RedrawBackBuffer
    RaiseEvent GotFocusAPI
End Sub

Private Sub ucSupport_LostFocusAPI()
    If m_PopUpVisible Then HideListBox
    m_FocusRectActive = False
    RedrawBackBuffer
    RaiseEvent LostFocusAPI
End Sub

Private Sub ucSupport_ClickCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    UpdateMousePosition x, y
    If m_MouseInComboRect And (Me.ListCount > 1) Then RaiseListBox
End Sub

Private Sub ucSupport_KeyDownCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    If m_PopUpVisible Then
        lbPrimary.NotifyKeyDown Shift, vkCode, markEventHandled
    Else
        listSupport.NotifyKeyDown Shift, vkCode, markEventHandled
    End If
End Sub

Private Sub ucSupport_KeyUpCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    listSupport.NotifyKeyUp Shift, vkCode, markEventHandled
End Sub

Private Sub ucSupport_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    UpdateMousePosition x, y
    RedrawBackBuffer
End Sub

Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    UpdateMousePosition x, y
End Sub

Private Sub ucSupport_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    UpdateMousePosition -100, -100
End Sub

Private Sub ucSupport_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    UpdateMousePosition x, y
End Sub

Private Sub ucSupport_MouseUpCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal ClickEventAlsoFiring As Boolean)
    RedrawBackBuffer
End Sub

Private Sub UpdateMousePosition(ByVal mouseX As Single, ByVal mouseY As Single)
    
    Dim mouseCheck As Boolean
    mouseCheck = Math_Functions.IsPointInRectF(mouseX, mouseY, m_ComboRect)
    
    If m_MouseInComboRect <> mouseCheck Then
        m_MouseInComboRect = mouseCheck
        If m_MouseInComboRect Then ucSupport.RequestCursor IDC_HAND Else ucSupport.RequestCursor IDC_DEFAULT
        RedrawBackBuffer
    End If
    
End Sub

'Unlike a regular listview, where the mousewheel results in pixel-level content scrolling, a closed dropdown scrolls actual
' list values one-at-a-time on each wheel motion.
Private Sub ucSupport_MouseWheelVertical(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal scrollAmount As Double)
    listSupport.NotifyMouseWheelVertical Button, Shift, x, y, scrollAmount
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub ucSupport_VisibilityChange(ByVal newVisibility As Boolean)
    If newVisibility Then
        listSupport.SetAutomaticRedraws True, True
    Else
        If m_PopUpVisible Then HideListBox
    End If
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    UpdateControlLayout
End Sub

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd
    ucSupport.RequestCaptionSupport False
    ucSupport.RequestExtraFunctionality True, True
    ucSupport.SpecifyRequiredKeys VK_DOWN, VK_UP, VK_PAGEDOWN, VK_PAGEUP, VK_HOME, VK_END, VK_RETURN, VK_SPACE, VK_ESCAPE
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDDROPDOWNFONT_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDDropDownFont", colorCount
    If (Not g_IsProgramRunning) Then UpdateColorList
    
    'Initialize a helper list class; it manages the actual list data, and a bunch of rendering and layout decisions
    Set listSupport = New pdListSupport
    listSupport.SetAutomaticRedraws False
    listSupport.ListSupportMode = PDLM_COMBOBOX
    
    'Prep font-specific managers and renderers
    Set m_listOfFonts = New pdStringStack
    
    'Initialize our font collection.  This is used to store a copy of each font face, as it's encountered, which we use to render preview
    ' text on the right side of the font dropdown.
    Set m_FontCollection = New pdFontCollection
    m_FontCollection.SetCacheSize NUM_ITEMS_VISIBLE * 3 + 1
    m_FontCollection.SetExtendedPropertyCaching True
    
    'Create demo strings, to be rendered in the drop-down using the current font face
    m_Text_Default = "AaBbCc 123"
    m_Text_EN = "Sample"
    m_Text_CJK = ChrW(&H6837) & ChrW(&H672C)
    m_Text_Arabic = ChrW(&H639) & ChrW(&H64A) & ChrW(&H646) & ChrW(&H629)
    m_Text_Hebrew = ChrW(&H5D3) & ChrW(&H5D5) & ChrW(&H5BC) & ChrW(&H5D2) & ChrW(&H5DE) & ChrW(&H5B8) & ChrW(&H5D4)
    
    'Update the control size parameters at least once
    UpdateControlLayout
    
End Sub

Private Sub UserControl_InitProperties()
    BackgroundColor = vbWhite
    UseCustomBackgroundColor = False
    Caption = ""
    Enabled = True
    FontSize = 10
    FontSizeCaption = 12
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    If (Not g_IsProgramRunning) Then ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        BackgroundColor = .ReadProperty("BackgroundColor", vbWhite)
        UseCustomBackgroundColor = .ReadProperty("UseCustomBackgroundColor", False)
        Caption = .ReadProperty("Caption", "")
        Enabled = .ReadProperty("Enabled", True)
        FontSize = .ReadProperty("FontSize", 10)
        FontSizeCaption = .ReadProperty("FontSizeCaption", 12)
    End With
End Sub

Private Sub UserControl_Resize()
    If (Not g_IsProgramRunning) Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_Terminate()
    'As a failsafe, immediately release the popup box.  (If we don't do this, PD will crash.)
    If m_PopUpVisible Then HideListBox
    If Not (m_SubclassReleaseTimer Is Nothing) Then m_SubclassReleaseTimer.StopTimer
    SafelyRemoveSubclass
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "BackgroundColor", m_BackgroundColor, vbWhite
        .WriteProperty "UseCustomBackgroundColor", m_UseCustomBackgroundColor, False
        .WriteProperty "Caption", Me.Caption, ""
        .WriteProperty "Enabled", Me.Enabled, True
        .WriteProperty "FontSize", Me.FontSize, 10
        .WriteProperty "FontSizeCaption", ucSupport.GetCaptionFontSize, 12
    End With
End Sub

Private Sub RaiseListBox()
    
    On Error GoTo UnexpectedListBoxTrouble
    
    If (Not ucSupport.AmIVisible) Or (Not ucSupport.AmIEnabled) Then Exit Sub
    
    'We first want to retrieve this control instance's window coordinates *in the screen's coordinate space*.
    ' (We need this to know how to position the listbox element.)
    Dim myRect As RECTL
    GetWindowRect Me.hWnd, myRect
    
    'We now want to figure out the idealized coordinates for the pop-up rect.  I prefer an OSX / Windows 10 approach to
    ' positioning, where the currently selected item (.ListIndex) is positioned directly over the underlying combo box,
    ' with neighboring entries positioned above and/or below, as relevant.
    Dim popupRect As RECTF, topOfListIndex As Single
    
    'To construct this rect, we start by calculating the position of the .ListIndex item itself
    With popupRect
        If ucSupport.IsCaptionActive Then
            .Left = myRect.Left + FixDPI(8)
            .Top = myRect.Top + (ucSupport.GetCaptionBottom + 2)
        Else
            .Left = myRect.Left
            .Top = myRect.Top
        End If
        .Width = myRect.Right - .Left
        .Height = listSupport.DefaultItemHeight
    End With
    
    topOfListIndex = popupRect.Top
    
    'Specific to the font dropdown, we are now going to calculate a new width (as necessary).  This is required because
    ' the list contains additional font preview data that the closed box does not.
    Dim i As Long
    If (m_LargestWidth = 0) Then
        
        'Create a temporary DIB so we don't have to constantly re-select the font into a DC of its own making.
        Dim tmpDC As Long
        tmpDC = Drawing.GetMemoryDC()
        
        'Font names are rendered in the current UI font
        Dim curFont As pdFont
        Set curFont = Font_Management.GetMatchingUIFont(m_FontSize)
        curFont.AttachToDC tmpDC
        
        'Find the longest font name
        Dim tmpWidth As Long
        For i = 0 To m_listOfFonts.GetNumOfStrings - 1
            tmpWidth = curFont.GetWidthOfString(m_listOfFonts.GetString(i))
            If (tmpWidth > m_LargestWidth) Then m_LargestWidth = tmpWidth
        Next i
        
        curFont.ReleaseFromDC
        Drawing.FreeMemoryDC tmpDC
        
        'The "best" width of the dropdown is a little sketchy, due to the font previews on the right.  At present,
        ' Use the width of the largest font name (which can only be 32 chars), multiplied by 2 (so an equal amount of size is allotted for
        ' the preview), plus a few extra pixels for padding, so a long font name with a long font preview don't "smash" together.
        m_LargestWidth = m_LargestWidth * 2.35
        
    End If
    
    popupRect.Width = m_LargestWidth
    
    'Next, we want to determine how many preceding and trailing entries are in the list.  (We keep a running tally of how
    ' many items theoretically appear in the current list, because we want to make sure that at least a certain amount are
    ' visible in the dropdown, if possible.)  These are purposefully declared as singles, as you'll see in subsequent steps.
    Dim amtPreceding As Single, amtTrailing As Single
    If Me.ListIndex > 0 Then amtPreceding = Me.ListIndex Else amtPreceding = 0
    
    If Me.ListIndex >= (Me.ListCount - 1) Then
        amtTrailing = 0
    ElseIf Me.ListIndex < 0 Then
        amtTrailing = Me.ListCount - 1
    Else
        amtTrailing = (Me.ListCount - 1) - Me.ListIndex
    End If
    
    'If the *total* possible amount of items is larger than the previously set NUM_ITEMS_VISIBLE constant, reduce the
    ' numbers proportionally.
    Dim amtToReduceList As Long
    If amtPreceding + amtTrailing > NUM_ITEMS_VISIBLE Then
    
        amtToReduceList = (amtPreceding + amtTrailing) - NUM_ITEMS_VISIBLE
        
        'This step may look weird, but conceptually, it's very simple.  We want to repeatedly reduce the size of the
        ' largest group of dropdown items - either the preceding or trailing group - until one of two things happens:
        ' 1) the two groups are equal in size, or
        ' 2) we reach our "amount to reduce list" target
        ' If (1) is reached before (2), we switch to reducing both groups by one element on each iteration
        Do
        
            If amtPreceding > amtTrailing Then
                amtPreceding = amtPreceding - 1
                amtToReduceList = amtToReduceList - 1
            ElseIf amtTrailing > amtPreceding Then
                amtTrailing = amtTrailing - 1
                amtToReduceList = amtToReduceList - 1
            Else
                amtPreceding = amtPreceding - 1
                amtTrailing = amtTrailing - 1
                amtToReduceList = amtToReduceList - 2
            End If
        
        Loop While amtToReduceList > 0
        
        'We now know exactly how many items we can display above and below the current entry, with a maximum of
        ' NUM_ITEMS_VISIBLE if possible.
        
    End If
    
    'Convert the preceding and trailing list item counts into pixel measurements, and add them to our target rect.
    Dim sizeChange As Single
    If amtPreceding > 0 Then
        sizeChange = amtPreceding * listSupport.DefaultItemHeight
        popupRect.Top = popupRect.Top - sizeChange
        popupRect.Height = popupRect.Height + sizeChange
    End If
    
    If amtTrailing > 0 Then
        sizeChange = amtTrailing * listSupport.DefaultItemHeight
        popupRect.Height = popupRect.Height + sizeChange
    End If
    
    'We now want to make sure the popup box doesn't lie off-screen.  Check each dimension in turn, and note that changing
    ' the vertical position of the listbox also changes the pixel-based position of the active .ListIndex within the box.
    If popupRect.Top < g_Displays.GetDesktopTop Then
        sizeChange = g_Displays.GetDesktopTop - popupRect.Top
        popupRect.Top = g_Displays.GetDesktopTop
        topOfListIndex = topOfListIndex + sizeChange
    Else
        
        Dim estimatedDesktopBottom As Long
        estimatedDesktopBottom = (g_Displays.GetDesktopTop + g_Displays.GetDesktopHeight) - g_Displays.GetTaskbarHeight
        
        If popupRect.Top + popupRect.Height > estimatedDesktopBottom Then
            sizeChange = (popupRect.Top + popupRect.Height) - estimatedDesktopBottom
            popupRect.Top = popupRect.Top - sizeChange
            topOfListIndex = topOfListIndex - sizeChange
        End If
        
    End If

    If popupRect.Left < g_Displays.GetDesktopLeft Then
        sizeChange = g_Displays.GetDesktopLeft - popupRect.Left
        popupRect.Left = g_Displays.GetDesktopLeft
    ElseIf popupRect.Left + popupRect.Width > g_Displays.GetDesktopLeft + g_Displays.GetDesktopWidth Then
        sizeChange = (popupRect.Left + popupRect.Width) - (g_Displays.GetDesktopLeft + g_Displays.GetDesktopWidth)
        popupRect.Left = popupRect.Left - sizeChange
    End If
    
    'We now have an idealized position rect for the list.  Because listbox scrollbars work in pixel increments, we can now
    ' convert the position of the active .ListIndex item from screen coords into relative coords.
    topOfListIndex = topOfListIndex - popupRect.Top
    
    'The list box is now ready to go.  Before displaying it, we want to convert the listbox to a floating toolbox window
    ' and a bare child of the desktop (hWnd = 0).  This allows the listbox to be positioned outside our boundary rect.
    m_PopUpHwnd = lbPrimary.hWnd
    If (Not m_WindowStyleHasBeenSet) Then
        m_WindowStyleHasBeenSet = True
        SetWindowLong m_PopUpHwnd, GWL_EXSTYLE, GetWindowLong(lbPrimary.hWnd, GWL_EXSTYLE) Or WS_EX_TOOLWINDOW
    End If
    SetParent m_PopUpHwnd, 0&
    
    'Move the listbox into position *but do not display it*
    With popupRect
        SetWindowPos m_PopUpHwnd, 0&, .Left, .Top, .Width, .Height, SWP_NOACTIVATE
    End With
    
    'Clone our list's contents; note that we cannot do this until *after* the list size has been established, as the
    ' scroll bar's maximum value is contingent on the available pixel size of the dropdown.
    lbPrimary.CloneExternalListSupport listSupport, topOfListIndex, PDLM_LB_INSIDE_CB
    
    'Now we can show the window
    With popupRect
        SetWindowPos m_PopUpHwnd, 0&, .Left, .Top, .Width, .Height, SWP_SHOWWINDOW
    End With
    
    'One last thing: because this is a (fairly?  mostly?  extremely?) hackish way to emulate a combo box, we need to cover the
    ' case where the user selects outside the raised list box, but *not* on an object that can receive focus (e.g. an exposed
    ' section of an underlying form).  Focusable objects are taken care of automatically, because a LostFocus event will fire,
    ' but non-focusable clicks are problematic.  To solve this, we subclass our parent control and watch for mouse events.
    ' Also, since we're subclassing the control anyway, we'll also hide the ListBox if the parent window is moved.
    m_ParentHWnd = UserControl.Parent.hWnd
    If (m_ParentHWnd <> 0) Then
        
        'Make sure we're not currently trying to release a previous subclass attempt
        Dim subclassActive As Boolean: subclassActive = False
        If Not (m_SubclassReleaseTimer Is Nothing) Then
            If m_SubclassReleaseTimer.IsActive Then
                m_SubclassReleaseTimer.StopTimer
                subclassActive = True
            End If
        End If
        
        If (Not subclassActive) And (Not m_SubclassActive) Then
            If (m_Subclass Is Nothing) Then Set m_Subclass = New cSelfSubHookCallback
            m_Subclass.ssc_Subclass m_ParentHWnd, 0, 1, Me
            m_Subclass.ssc_AddMsg m_ParentHWnd, MSG_BEFORE, WM_ENTERSIZEMOVE, WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_WINDOWPOSCHANGING
            m_SubclassActive = True
        End If
        
    End If
    
    'As an additional failsafe, we also notify the master UserControl tracker that a list box is active.  If any other PD control
    ' receives focus, that tracker will automatically unload our list box as well, "just in case"
    UserControl_Support.NotifyDropDownChangeState Me.hWnd, m_PopUpHwnd, True
    
    m_PopUpVisible = True
    
    Exit Sub
    
UnexpectedListBoxTrouble:

    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "WARNING!  pdDropDown.RaiseListBox failed because of Err # " & Err.Number & ", " & Err.Description
    #End If
    
End Sub

Private Sub HideListBox()

    If m_PopUpVisible And (m_PopUpHwnd <> 0) Then
        
        'Notify the master UserControl tracker that our list box is now inactive.
        UserControl_Support.NotifyDropDownChangeState Me.hWnd, m_PopUpHwnd, False
        
        m_PopUpVisible = False
        SetParent m_PopUpHwnd, Me.hWnd
        g_WindowManager.SetVisibilityByHWnd m_PopUpHwnd, False
        m_PopUpHwnd = 0
        
        'Note that termination may result in the client site not being available.  If this happens, we simply want
        ' to continue; the subclasser will handle clean-up automatically.
        SafelyRemoveSubclass
        
        'Restoring window styles proves unnecessary (and in fact, it can fuck things up - so just leave the style bits as
        ' we set them previously!)
        'SetWindowLong lbPrimary.hWnd, GWL_EXSTYLE, GetWindowLong(lbPrimary.hWnd, GWL_EXSTYLE) And CLng(Not WS_EX_TOOLWINDOW)
        
    End If
    
End Sub

'If a hook exists, uninstall it.  DO NOT CALL THIS FUNCTION if the class is currently inside the hook proc.
Private Sub RemoveSubclass()
    If (Not (m_Subclass Is Nothing)) And (m_ParentHWnd <> 0) And m_SubclassActive Then
        On Error GoTo UnsubclassUnnecessary
        m_Subclass.ssc_UnSubclass m_ParentHWnd
        m_ParentHWnd = 0
        m_SubclassActive = False
    End If
UnsubclassUnnecessary:
End Sub

'Release the edit box's keyboard hook.  In some circumstances, we can't do this immediately, so we set a timer that will
' release the hook as soon as the system allows.
Private Sub SafelyRemoveSubclass()
    If m_InSubclassNow Then
        If (m_SubclassReleaseTimer Is Nothing) Then Set m_SubclassReleaseTimer = New pdTimer
        m_SubclassReleaseTimer.Interval = 16
        m_SubclassReleaseTimer.StartTimer
    Else
        RemoveSubclass
    End If
End Sub

'Whenever a control property changes that affects control size or layout (including internal changes, like caption adjustments),
' call this function to recalculate the control's internal layout
Private Sub UpdateControlLayout()
    
    'This control auto-sizes its height to match the current font.  To make it a different size, adjust the padding
    ' constants at the top of this module.
    Dim desiredControlHeight As Long
    If ucSupport.IsCaptionActive Then desiredControlHeight = ucSupport.GetCaptionBottom + 2 Else desiredControlHeight = 0
    desiredControlHeight = desiredControlHeight + m_IdealComboBoxHeight + COMBO_PADDING_VERTICAL * 2
    
    'Apply the new height to this UC instance, as necessary
    If ucSupport.GetControlHeight <> desiredControlHeight Then
        ucSupport.RequestNewSize , desiredControlHeight, True
        Exit Sub
    End If
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Next, determine the positioning of the caption, if present.  (ucSupport.GetCaptionBottom tells us where the
    ' caption text ends vertically.)
    If ucSupport.IsCaptionActive Then
        
        'The dropdown area is placed relative to the caption
        With m_ComboRect
            .Left = FixDPI(8)
            .Top = ucSupport.GetCaptionBottom + 3
            .Width = (bWidth - 2) - .Left
            .Height = (bHeight - 2) - .Top
        End With
        
    'If there's no caption, allow the clickable portion to fill the entire control
    Else
        
        With m_ComboRect
            .Left = 1
            .Top = 1
            .Width = (bWidth - 2) - .Left
            .Height = (bHeight - 2) - .Top
        End With
        
    End If
    
    'Notify the list manager of our new size.  (Note that this isn't necessary from a rendering standpoint, as we don't
    ' render a normal list-type UI to the dropdown - but the listSupport class won't raise Redraw events if it has an
    ' invalid rendering rect.)
    listSupport.NotifyParentRectF m_ComboRect
    
    'With all size metrics handled, we can now paint the back buffer
    RedrawBackBuffer True
            
End Sub

'Primary rendering function.  Note that ucSupport handles a number of rendering duties (like maintaining a back buffer for us).
Private Sub RedrawBackBuffer(Optional ByVal redrawImmediately As Boolean = False)
    
    'We can improve shutdown performance by ignoring redraw requests when the program is going down
    If g_ProgramShuttingDown Then
        If (g_Themer Is Nothing) Then Exit Sub
    End If
    
    'Figure out which background color to use.  This is normally determined by theme, but individual buttons also allow
    ' a custom .BackColor property (important if this instance lies atop a non-standard background, like a command bar).
    Dim finalBackColor As Long
    If m_UseCustomBackgroundColor Then finalBackColor = m_BackgroundColor Else finalBackColor = m_Colors.RetrieveColor(PDDD_Background, Me.Enabled)
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long, bWidth As Long, bHeight As Long
    bufferDC = ucSupport.GetBackBufferDC(True, finalBackColor)
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Thanks to the v7.0 theming overhaul, it's completely safe to retrieve colors in the IDE, so we no longer
    ' need to handle these specially.
    Dim ddColorBorder As Long, ddColorFill As Long, ddColorText As Long, ddColorArrow As Long
    ddColorBorder = m_Colors.RetrieveColor(PDDD_ComboBorder, Me.Enabled, False, m_MouseInComboRect Or m_FocusRectActive)
    ddColorFill = m_Colors.RetrieveColor(PDDD_ComboFill, Me.Enabled, False, m_MouseInComboRect Or m_FocusRectActive)
    ddColorText = m_Colors.RetrieveColor(PDDD_DropDownCaption, Me.Enabled, False, m_MouseInComboRect Or m_FocusRectActive)
    ddColorArrow = m_Colors.RetrieveColor(PDDD_DropArrow, Me.Enabled, False, m_MouseInComboRect Or m_FocusRectActive)
    
    If g_IsProgramRunning Then
        
        'First, fill the combo area interior with the established fill color
        GDI_Plus.GDIPlusFillRectFToDC bufferDC, m_ComboRect, ddColorFill, 255
        
        'A border is always drawn around the control; its size and color vary by hover state, however.
        Dim borderWidth As Single
        If m_MouseInComboRect Or m_FocusRectActive Then borderWidth = 3 Else borderWidth = 1
        GDI_Plus.GDIPlusDrawRectFOutlineToDC bufferDC, m_ComboRect, ddColorBorder, 255, borderWidth, False, GP_LJ_Miter
        
        'Next, the right-aligned arrow.  (We need its measurements to know where to restrict the caption's length.)
        Dim buttonPt1 As POINTFLOAT, buttonPt2 As POINTFLOAT, buttonPt3 As POINTFLOAT
        buttonPt1.x = m_ComboRect.Left + m_ComboRect.Width - FixDPIFloat(16)
        buttonPt1.y = m_ComboRect.Top + (m_ComboRect.Height / 2) - FixDPIFloat(1)
        
        buttonPt3.x = m_ComboRect.Left + m_ComboRect.Width - FixDPIFloat(8)
        buttonPt3.y = buttonPt1.y
        
        buttonPt2.x = buttonPt1.x + (buttonPt3.x - buttonPt1.x) / 2
        buttonPt2.y = buttonPt1.y + FixDPIFloat(3)
        
        GDI_Plus.GDIPlusDrawLineToDC bufferDC, buttonPt1.x, buttonPt1.y, buttonPt2.x, buttonPt2.y, ddColorArrow, 255, 2, True, GP_LC_Round
        GDI_Plus.GDIPlusDrawLineToDC bufferDC, buttonPt2.x, buttonPt2.y, buttonPt3.x, buttonPt3.y, ddColorArrow, 255, 2, True, GP_LC_Round
        
        Dim arrowLeftLimit As Single
        arrowLeftLimit = buttonPt1.x - FixDPI(2)
        
        'For an OSX-type look, we can mirror the arrow across the control's center line, then draw it again; I personally prefer
        ' this behavior (as the list box may extend up or down), but I'm not sold on implementing it just yet, because it's out of place
        ' next to regular Windows drop-downs...
        'buttonPt1.y = fullWinRect.Bottom - buttonPt1.y
        'buttonPt2.y = fullWinRect.Bottom - buttonPt2.y
        'buttonPt3.y = fullWinRect.Bottom - buttonPt3.y
        '
        'GDI_Plus.GDIPlusDrawLineToDC targetDC, buttonPt1.x, buttonPt1.y, buttonPt2.x, buttonPt2.y, cboButtonColor, 255, 2, True, GP_LC_Round
        'GDI_Plus.GDIPlusDrawLineToDC targetDC, buttonPt2.x, buttonPt2.y, buttonPt3.x, buttonPt3.y, cboButtonColor, 255, 2, True, GP_LC_Round
        
        'Finally, paint the caption, and restrict its length to the available dropdown space
        If (Me.ListIndex <> -1) Then
        
            Dim tmpFont As pdFont
            Set tmpFont = Font_Management.GetMatchingUIFont(Me.FontSize)
            tmpFont.SetFontColor ddColorText
            tmpFont.SetTextAlignment vbLeftJustify
            tmpFont.AttachToDC bufferDC
            
            With m_ComboRect
                tmpFont.FastRenderTextWithClipping .Left + COMBO_PADDING_HORIZONTAL, .Top + COMBO_PADDING_VERTICAL, arrowLeftLimit, .Height, listSupport.List(Me.ListIndex, False), True, True
            End With
            
            tmpFont.ReleaseFromDC
            Set tmpFont = Nothing
            
        End If
        
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint redrawImmediately
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    With m_Colors
        .LoadThemeColor PDDD_Background, "Background", IDE_WHITE
        .LoadThemeColor PDDD_ComboFill, "ComboFill", IDE_WHITE
        .LoadThemeColor PDDD_ComboBorder, "ComboBorder", IDE_GRAY
        .LoadThemeColor PDDD_DropDownCaption, "Caption", IDE_GRAY
        .LoadThemeColor PDDD_DropArrow, "DropArrow", IDE_GRAY
        .LoadThemeColor PDDD_ListCaption, "ListCaption", IDE_GRAY
        .LoadThemeColor PDDD_ListBorder, "ListBorder", IDE_GRAY
    End With
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme()
    UpdateColorList
    listSupport.UpdateAgainstCurrentTheme
    If g_IsProgramRunning Then ucSupport.UpdateAgainstThemeAndLanguage
    lbPrimary.UpdateAgainstCurrentTheme
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub

'All messages subclassed by m_Subclass are handled here.
Private Sub myWndProc(ByVal bBefore As Boolean, _
                      ByRef bHandled As Boolean, _
                      ByRef lReturn As Long, _
                      ByVal lng_hWnd As Long, _
                      ByVal uMsg As Long, _
                      ByVal wParam As Long, _
                      ByVal lParam As Long, _
                      ByRef lParamUser As Long)
'*************************************************************************************************
'* bBefore    - Indicates whether the callback is before or after the original WndProc. Usually
'*              you will know unless the callback for the uMsg value is specified as
'*              MSG_BEFORE_AFTER (both before and after the original WndProc).
'* bHandled   - In a before original WndProc callback, setting bHandled to True will prevent the
'*              message being passed to the original WndProc and (if set to do so) the after
'*              original WndProc callback.
'* lReturn    - WndProc return value. Set as per the MSDN documentation for the message value,
'*              and/or, in an after the original WndProc callback, act on the return value as set
'*              by the original WndProc.
'* lng_hWnd   - Window handle.
'* uMsg       - Message value.
'* wParam     - Message related data.
'* lParam     - Message related data.
'* lParamUser - User-defined callback parameter. Change vartype as needed (i.e., Object, UDT, etc)
'*************************************************************************************************
    
    m_InSubclassNow = True
    
    'We don't actually care about parsing out individual messages here.  This function will only be called by subclassed messages
    ' that result in the listbox being closed.
    If m_PopUpVisible Then HideListBox
    
    m_InSubclassNow = False
    bHandled = False

' *************************************************************
' C A U T I O N   C A U T I O N   C A U T I O N   C A U T I O N
' -------------------------------------------------------------
' DO NOT ADD ANY OTHER CODE BELOW THE "END SUB" STATEMENT BELOW
'   add this warning banner to the last routine in your class
' *************************************************************
End Sub

