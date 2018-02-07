parser grammar BookishParser;

@header {
import java.util.Map;
import java.util.HashMap;
import us.parr.lib.ParrtStrings;
import us.parr.bookish.model.entity.*;
import static us.parr.bookish.translate.Translator.splitSectionTitle;
}

options {
	tokenVocab=BookishLexer;
}

@members {
	/** Global labeled entities such as citations, figures, websites.
	 *  Collected from all input markdown files.
	 *
	 *  Track all labeled entities in this file for inclusion in overall book.
	 *  Do during parse for speed, to avoid having to walk tree 2x.
	 */
	public Map<String,EntityDef> entities = new HashMap<>();

	public void defEntity(EntityDef entity) {
		if ( entity.label!=null ) {
			if ( entities.containsKey(entity.label) ) {
				System.err.printf("line %d: redefinition of label %s\n",
				 entity.getStartToken().getLine(), entity.label);
			}
			entities.put(entity.label, entity);
			System.out.println("Def "+entity);
		}
	}

	// Each parser (usually per doc/chapter) keeps its own counts for sections, figures, sidenotes, web links, ...

	public int defCounter = 1;
	public int figCounter = 1; // track 1..n for whole chapter.
	public int secCounter = 1;
	public int subSecCounter = 1;
	public int subSubSecCounter = 1;

	public int chapNumber;

	public ChapterDef currentChap;
	public SectionDef currentSec;
	public SubSectionDef currentSubSec;
	public SubSubSectionDef currentSubSubSec;

	public BookishParser(TokenStream input, int chapNumber) {
		this(input);
		this.chapNumber = chapNumber;
	}
}

document
	:	chapter BLANK_LINE? EOF
	;

chapter : BLANK_LINE? chap=CHAPTER author? preabstract? abstract_? (section_element|ws)* section*
		  {
		  currentChap = new ChapterDef(chapNumber, $chap, null);
		  defEntity(currentChap);
		  }
		;

author : (ws|BLANK_LINE)? AUTHOR LCURLY paragraph_optional_blank_line RCURLY ;

abstract_ : (ws|BLANK_LINE)? ABSTRACT LCURLY paragraph_optional_blank_line paragraph* RCURLY;

preabstract : (ws|BLANK_LINE)? PREABSTRACT LCURLY paragraph_optional_blank_line paragraph* RCURLY;

section : BLANK_LINE sec=SECTION (section_element|ws)* subsection*
		  {
		  subSecCounter = 1;
		  subSubSecCounter = 1;
		  currentSubSec = null;
		  currentSubSubSec = null;
		  currentSec = new SectionDef(secCounter, $sec, currentChap);
		  defEntity(currentSec);
		  secCounter++;
		  }
		;

subsection : BLANK_LINE sec=SUBSECTION (section_element|ws)* subsubsection*
		  {
		  subSubSecCounter = 1;
		  currentSubSubSec = null;
		  currentSubSec = new SubSectionDef(subSecCounter, $sec, currentSec);
		  defEntity(currentSubSec);
		  subSecCounter++;
		  }
		;

subsubsection : BLANK_LINE sec=SUBSUBSECTION (section_element|ws)*
		  {
		  currentSubSubSec = new SubSubSectionDef(subSubSecCounter, $sec, currentSubSec);
		  defEntity(currentSubSubSec);
		  subSubSecCounter++;
		  }
		;

section_element
	:	paragraph
	|	BLANK_LINE?
	 	(	link
		|	eqn
		|	block_eqn
		|	ordered_list
		|	unordered_list
		|	table
		|	block_image
		|	latex
		|	xml
		|	site
		|	citation
		|	sidequote
		|	sidenote
		|	chapquote
		|	sidefig
		|	figure
		)
	|	other
	;

site      : SITE REF ws? block
			{defEntity(new SiteDef(defCounter++, $REF, $block.text));}
		  ;

citation  : CITATION REF ws? t=block ws? a=block
			{defEntity(new CitationDef(defCounter++, $REF, $t.text, $a.text));}
		  ;

chapquote : CHAPQUOTE q=block ws? a=block
		  ;

sidequote : SIDEQUOTE (REF ws?)? q=block ws? a=block
			{if ($REF!=null) defEntity(new SideQuoteDef(defCounter++, $REF, $q.text, $a.text));}
		  ;

sidenote  : CHAPQUOTE (REF ws?)? block
			{if ($REF!=null) defEntity(new SideNoteDef(defCounter++, $REF, $block.text));}
		  ;

sidefig   : SIDEFIG REF? ws? code=block (ws? caption=block)?
			{if ($REF!=null) defEntity(new SideFigDef(figCounter++, $REF, $code.text, $caption.text));}
		  ;

figure    : FIGURE REF? ws? code=block (ws? caption=block)?
			{if ($REF!=null) defEntity(new FigureDef(figCounter++, $REF, $code.text, $caption.text));}
		  ;

block : LCURLY paragraph_content? RCURLY ;

paragraph
	:	BLANK_LINE paragraph_content
	;

paragraph_optional_blank_line
	:	BLANK_LINE? paragraph_content
	;

paragraph_content
	:	(paragraph_element|quoted|firstuse|inline_code|ws)+
	;

paragraph_element
	:	eqn
    |	link
    |	italics
    |	bold
    |	image
	|	xml
	|	ref
	|	symbol
	|	other
	;

ref : REF ;

symbol : SYMBOL REF ; // e.g., \symbol[degree], \symbol[tm]

quoted : QUOTE (paragraph_element|ws)+ QUOTE ;

inline_code : BACKTICK (paragraph_element|ws)+ BACKTICK ;

firstuse : FIRSTUSE block ;

latex : LATEX ;

ordered_list
	:	OL
		( ws? LI ws? list_item )+ ws?
		OL_
	;

unordered_list
	:	UL
		( ws? LI ws? list_item )+ ws?
		UL_
	;

table
	:	TABLE
			( ws? table_header )? // header row
			( ws? table_row )+ // actual rows
			ws?
		TABLE_
	;

table_header : TR ws? (TH attrs END_OF_TAG table_item)+ ;
table_row : TR ws? (TD table_item)+ ;

list_item : (section_element|paragraph_element|quoted|firstuse|inline_code|ws|BLANK_LINE)* ;

table_item : (section_element|paragraph_element|quoted|firstuse|inline_code|ws|BLANK_LINE)* ;

block_image : image ;

image : IMG attrs END_OF_TAG ;

attrs returns [Map<String,String> attrMap = new HashMap<>()] : attr_assignment[$attrMap]* ;

attr_assignment[Map<String,String> attrMap]
	:	name=XML_ATTR XML_EQ value=XML_ATTR_VALUE
		{$attrMap.put($name.text,ParrtStrings.stripQuotes($value.text));}
	;

xml	: XML tagname=XML_ATTR attrs END_OF_TAG | END_TAG ;

link 		:	LINK ;
italics 	:	ITALICS ;
bold 		:	BOLD ;
other       :	OTHER | POUND ;

block_eqn : BLOCK_EQN ;

eqn : EQN ;

ws : (SPACE | NL | TAB)+ ;
