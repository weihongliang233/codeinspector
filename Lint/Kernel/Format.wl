BeginPackage["Lint`Format`"]

LintMarkup

LintBold


LintSpaceIndicator::usage = "LintSpaceIndicator represents a space indicator in formatted output."

LintErrorIndicator::usage = "LintErrorIndicator represented an error indicator in formatted output."

LintContinuation::usage = "LintContinuation represents a continuation in formatted output."

LintTimes::usage = "LintTimes represents a times operator in formatted output."

LintEOF::usage = "LintEOF represents an EOF in formatted output."


Begin["`Private`"]

Needs["AST`"]
Needs["AST`Utils`"]
Needs["Lint`"]
Needs["Lint`Utils`"]



(*

The values for both $LintedLineWidth and $LintedLintItemSize are derived heuristically

$LintedLintItemSize is adjusted first to allow mixes of regular characters, \[SpaceIndicator], and \[ErrorIndicator] to
look good in a notebook.

Then $LintedLineWidth is adjusted to allow fitting inside a standard notebook window

*)

(*
How many ems for characters in the Grid ?

Somewhere between 0.606 and 0.607, \[ErrorIndicator] starts overlapping and actually overflow display on the cloud and looks bad

The desktop FE allows overlapping just fine

*)
$LintedLintItemSize = 0.65

(*
How many characters before partitioning a new line?
*)
$LintedLineWidth = 120











Format[lintedFile:LintedFile[file_String, lintedLines:{___LintedLine}], StandardForm] :=
	Interpretation[
		Column[{Row[{file}, ImageMargins -> {{0, 0}, {10, 10}}]} ~Join~ lintedLines, Left, 0, Background -> GrayLevel[0.95], Frame -> True]
		,
		lintedFile]

Format[lintedFile:LintedFile[file_String, lintedLines:{___LintedLine}], OutputForm] :=
	Column[{Row[{file}]} ~Join~ lintedLines, Left, 0]



Format[lintedString:LintedString[string_String, lintedLines:{___LintedLine}], StandardForm] :=
	Interpretation[
		Column[{Row[{string}, ImageMargins -> {{0, 0}, {10, 10}}]} ~Join~ lintedLines, Left, 0, Background -> GrayLevel[0.95], Frame -> True]
		,
		lintedString]

Format[lintedString:LintedString[string_String, lintedLines:{___LintedLine}], OutputForm] :=
	Column[{Row[{string}]} ~Join~ lintedLines, Left, 0]






(*
replace `` and ** markup
*)
boldify[s_String, form_] := StringReplace[s, {
  RegularExpression["``(.*?)``"] :> ToString[LintBold["$1"], form],
  RegularExpression["\\*\\*(.*?)\\*\\*"] :> ToString[LintBold["$1"], form]}]

gridify[s_String] := List /@ StringSplit[s, "\n", All]


Format[lint:Lint[tag_String, description_String, severity_String, data_Association], StandardForm] :=
Module[{g, bolded},

	bolded = boldify[description, StandardForm];

	g = gridify[bolded];

	g[[1]] = {LintBold[tag],
					Spacer[20],
					LintMarkup[Row[{"Severity: ", Row[{severity}]}], FontWeight->Bold, FontColor->severityColor[{lint}]],
					Spacer[20]} ~Join~ g[[1]];

  Interpretation[
  	Column[Row[#]& /@ g, {Left, Center}, Frame -> True, Background -> GrayLevel[0.85]],
  	lint]
]

Format[lint:Lint[tag_String, description_String, severity_String, data_Association], OutputForm] :=
Module[{g, bolded},

	bolded = boldify[description, OutputForm];

	g = gridify[bolded];

	g[[1]] = {LintBold[tag],
					" ",
					LintMarkup[Row[{"Severity: ", Row[{severity}]}], FontWeight->Bold, FontColor->severityColor[{lint}]],
					" " } ~Join~ g[[1]];

  Column[Row[#]& /@ g]
]








Options[LintedLine] = {
	"MaxLineNumberLength" -> 5,
	"Elided" -> False
}

(*
treat {list, list} as Underscript

I originally wanted to do this:
Style[Underscript[line, under], ScriptSizeMultipliers->1]

But there is no guarantee that monospace fonts will be respected
So brute-force it with Grid so that it looks good
*)
Format[LintedLine[lineSource_String, lineNumber_Integer, hash_String, {lineList_List, underlineList_List}, lints:{___Lint}, opts___], StandardForm] :=
Catch[
Module[{endingLints, elided, startingLints, grid, red, darkerOrange, blue, larger},

	elided = OptionValue[LintedLine, {opts}, "Elided"];

	If[elided,
		Throw[Grid[{{"\[SpanFromAbove]"}}, Alignment -> Center]]
	];

	startingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {{lineNumber, _}, _}]]];
	(*
	lints that are ending on this line
	format them
	*)
	endingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {_, {lineNumber, _}}]]];

	grid = Flatten[Transpose /@ Partition[Transpose[{lineList, underlineList}], UpTo[$LintedLineWidth]], 1];

	(*
	All possible styling options

	Bold is implied by any other markup
	*)
	red = Position[grid, LintMarkup[_, ___, FontColor -> Red, ___]];
	darkerOrange = Position[grid, LintMarkup[_, ___, FontColor -> Darker[Orange], ___]];
	blue = Position[grid, LintMarkup[_, ___, FontColor -> Blue, ___]];
	larger = Position[grid, LintMarkup[_, ___, FontSize -> Larger, ___]];

	(*
	Collect all of the adjacent positions of a style into a single range

	This is then fed into the Grid ItemStyle machinery for efficient rendering and space

	TODO: Ranges across rows could also be coalesced

	TODO: Combinations of styles could also be considered

	For example, it would be nice for the top row and the bottom row of an error to be a single range -> {Bold, Red}
	and then the underline could then add in -> {Larger}

	*)
	red = coalesce[red];
	darkerOrange = coalesce[darkerOrange];
	blue = coalesce[blue];
	larger = coalesce[larger];

	(*
	now remove markup from the grid itself
	*)
	grid = grid /. LintMarkup[content_, ___] :> content;

	(*
	Alignment option of Row has no effect: bug 93267
	So must use Grid in order to have formatLeftColumn[] aligned on top
	*)
	Grid[
		If[startingLints == {}, Sequence@@{}, {{Row[{Spacer[10]}]}}] ~Join~
		{{formatLeftColumn[lineSource, lineNumber, hash, opts], Spacer[10],
			Column[{Grid[grid,
						Spacings -> {0, 0},
						ItemSize -> $LintedLintItemSize,
						ItemStyle -> {Automatic, Automatic,
							(# -> {Bold, Red}& /@ red) ~Join~
							(# -> {Bold, Darker[Orange]}& /@ darkerOrange) ~Join~
							(# -> {Bold, Blue}& /@ blue) ~Join~
							(# -> {Bold, Larger}& /@ larger)} ] } ~Join~ endingLints]}} ~Join~
		If[endingLints == {}, Sequence@@{}, {{Row[{Spacer[10]}]}}]
		,
		Alignment -> Top, Spacings -> {0, 0}]
]]


coalesce[list_] :=
  {{#[[1]][[1]], #[[-1]][[1]]}, {#[[1]][[2]], #[[-1]][[2]]}}& /@ Split[list, #1[[1]] == #2[[1]] && #1[[2]] + 1 == #2[[2]]&]


(*
Grid has too much space in OutputForm, so use Column[{Row[], Row[]}]

Not possible to construct: ab
                           cd

with Grid in OutputForm. bug?
*)
(*
underlineList is not used in OutputForm
*)
Format[LintedLine[lineSource_String, lineNumber_Integer, hash_String, {lineList_List, underlineList_List}, lints:{___Lint}, opts___], OutputForm] :=
Catch[
Module[{maxLineNumberLength, paddedLineNumber, endingLints, elided, grid},

	maxLineNumberLength = OptionValue[LintedLine, {opts}, "MaxLineNumberLength"];
	elided = OptionValue[LintedLine, {opts}, "Elided"];

	If[elided,
		Throw[Grid[{{"\[SpanFromAbove]"}}, Alignment -> Center]]
	];

	paddedLineNumber = StringPadLeft[ToString[lineNumber], maxLineNumberLength, " "];

	(*
	lints that are ending on this line
	format them
	*)
	endingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {_, {lineNumber, _}}]]];

	grid = Flatten[Transpose /@ Partition[Transpose[{lineList, underlineList}], UpTo[$LintedLineWidth]], 1];

	Row[{Row[{"line ", paddedLineNumber, ": "}],
			Column[{Column[Row /@ grid]} ~Join~
			endingLints] }]
]]





Format[LintedLine[lineSource_String, lineNumber_Integer, hash_String, lineList_List, lints:{___Lint}, opts___], StandardForm] :=
Catch[
Module[{endingLints, elided, startingLints, grid},
	
	elided = OptionValue[LintedLine, {opts}, "Elided"];

	If[elided,
		Throw[Grid[{{"\[SpanFromAbove]"}}, Alignment -> Center]]
	];

	startingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {{lineNumber, _}, _}]]];
	(*
	lints that are ending on this line
	format them
	*)
	endingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {_, {lineNumber, _}}]]];

	grid = Partition[lineList, UpTo[$LintedLineWidth]];

	Grid[
		If[startingLints == {}, Sequence@@{}, {{Row[{Spacer[10]}]}}] ~Join~
		{{formatLeftColumn[lineSource, lineNumber, hash, opts], Spacer[20],
			Column[{Grid[grid,
						Spacings -> {0, 0}, ItemSize -> $LintedLintItemSize] } ~Join~ endingLints ]}} ~Join~
		If[endingLints == {}, Sequence@@{}, {{Row[{Spacer[10]}]}}],
			Alignment -> Top, Spacings -> {0, 0}]
]]

Format[LintedLine[lineSource_String, lineNumber_Integer, hash_String, lineList_List, lints:{___Lint}, opts___], OutputForm] :=
Catch[
Module[{maxLineNumberLength, paddedLineNumber, endingLints, elided, grid},

	maxLineNumberLength = OptionValue[LintedLine, {opts}, "MaxLineNumberLength"];
	elided = OptionValue[LintedLine, {opts}, "Elided"];

	If[elided,
		Throw[Grid[{{"\[SpanFromAbove]"}}, Alignment -> Center]]
	];

	paddedLineNumber = StringPadLeft[ToString[lineNumber], maxLineNumberLength, " "];

	(*
	lints that are ending on this line
	format them
	*)
	endingLints = Cases[lints, Lint[_, _, _, KeyValuePattern[Source -> {_, {lineNumber, _}}]]];

	grid = Partition[lineList, UpTo[$LintedLineWidth]];

	Row[{Row[{"line ", paddedLineNumber, ": "}], Column[{Column[Row /@ grid]} ~Join~ endingLints] }]
]]




Options[formatLeftColumn] = {
	"MaxLineNumberLength" -> 5
}

formatLeftColumn[lineSource_String, lineNumber_Integer, hash_String, opts___] :=
Catch[
Module[{label, maxLineNumberLength, paddedLineNumber},
	
	maxLineNumberLength = OptionValue[formatLeftColumn, {opts}, "MaxLineNumberLength"];
	
	paddedLineNumber = StringPadLeft[ToString[lineNumber], maxLineNumberLength, " "];

	label = Framed[Row[{"line", " ", paddedLineNumber, ":"}]];

	(*
	Copying in cloud:
	CLOUD-14729

	ActionMenu CopyToClipboard with Evaluator->None:
	bug 374583
	*)

	With[{escaped = escapeString[hash]},

	ActionMenu[
		Tooltip[
			label,
			"Click to open menu...", TooltipDelay -> Automatic], {
		"Copy line source" :> CopyToClipboard[lineSource],
		"Copy line number" :> CopyToClipboard[lineNumber],
		"Copy line hash" :> CopyToClipboard[escaped] }, Appearance -> None, DefaultBaseStyle -> {}]
	]
]]





(*
bug 351153
Cannot use characters like \[SpaceIndicator] and \[ErrorIndicator] in OutputForm and
get Grid alignment
*)

Format[LintSpaceIndicator, StandardForm] := "\[SpaceIndicator]"
Format[LintSpaceIndicator, OutputForm] := "~"

Format[LintErrorIndicator, StandardForm] := "\[ErrorIndicator]"
Format[LintErrorIndicator, OutputForm] := "^"

Format[LintContinuation, StandardForm] := "\[Continuation]"
Format[LintContinuation, OutputForm] := "\\"

Format[LintTimes, StandardForm] := "\[Times]"
Format[LintTimes, OutputForm] := "x"

Format[LintEOF, StandardForm] := "\[FilledSquare]"
Format[LintEOF, OutputForm] := "EOF"







Options[LintMarkup] = {
	FontColor -> Automatic,
	FontWeight -> Automatic,
	FontVariations -> Automatic,
	FontSize -> Automatic
}


(*
Windows console doesn't support ANSI escape sequences by default
But MacOSX and Unix should be fine
*)
$UseANSI = Catch[Switch[$OperatingSystem,
				"Windows",
				Module[{vals, level, ret},
					(*
					https://blogs.msdn.microsoft.com/commandline/2017/06/20/understanding-windows-console-host-settings/
					*)
					vals = Developer`ReadRegistryKeyValues["HKEY_CURRENT_USER\\Console"];
					If[FailureQ[vals],
						Throw[False]
					];
					level = "VirtualTerminalLevel" /. vals /. {"VirtualTerminalLevel" -> 0};
					ret = (level != 0);
					ret
				]
				,
				_,
				True
			]]

Format[LintMarkup[content_, opts___], StandardForm] := Style[content, opts]

Format[LintMarkup[content_, opts___], OutputForm] :=
Catch[
Module[{s, color, weight, setup},
	
	s = ToString[content, OutputForm];

	(*
	Notebook front end does not support ANSI escape sequences
	*)
	If[$Notebooks || !$UseANSI,
		Throw[s]
	];

	color = OptionValue[LintMarkup, {opts}, FontColor];
	weight = OptionValue[LintMarkup, {opts}, FontWeight];
	(* FontVariations is ignored for now *)
	(* FontSize is ignored for now *)

	(*
	The possibility of 38;5; sequences affecting the bold bit on Windows means that 
	weight should be set first.
	Still would like to completely understand the differences between platforms.
	*)
	setup = StringJoin[{weightANSICode[weight], colorANSICode[color]}];
	If[setup != "",
		(* only print reset if there is anything to reset *)
		s = StringJoin[{setup, s, resetANSICode[]}];
	];
	s
]]




LintBold[content_] := LintMarkup[content, FontWeight->Bold]



colorANSICode[GrayLevel[gray_]] :=
	With[{code = ToString[232 + Round[gray*23]]},
		"\[RawEscape][38;5;"<>code<>"m"
	]
colorANSICode[RGBColor[r_, g_, b_]] :=
	With[{code = ToString[16 + 36*Round[5*r] + 6*Round[5*g] + Round[5*b]]},
		"\[RawEscape][38;5;"<>code<>"m"
	]

(*
Use simpler sequences for common cases

This also works around an issue on Windows where the 38;5; sequences affect the bold bit
*)
colorANSICode[Black] := "\[RawEscape][30m"
colorANSICode[Red] := "\[RawEscape][31m"
colorANSICode[Green] := "\[RawEscape][32m"
colorANSICode[Yellow] := "\[RawEscape][33m"
colorANSICode[Blue] := "\[RawEscape][34m"
colorANSICode[Magenta] := "\[RawEscape][35m"
colorANSICode[Cyan] := "\[RawEscape][36m"
colorANSICode[White] := "\[RawEscape][37m"

colorANSICode[Automatic] = ""


weightANSICode[Bold] = "\[RawEscape][1m"
weightANSICode[Automatic] = ""

variationsANSICode[{"Underline"->True}] = "\[RawEscape][4m"
variationsANSICode[Automatic] = ""

resetANSICode[] = "\[RawEscape][0m"



End[]

EndPackage[]