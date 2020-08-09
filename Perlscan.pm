package Perlscan;
# ABSTRACT:  Lexical analysis module for Perl -- parses one line of Perl program (which should contain a complete statement) into tokens/lexems
#::          For alpha-testers only. Should be used with Pythoinizer testing suit
#::
#:: Copyright Nikolai Bezroukov, 2019.
#:: Licensed under Perl Artistic license# Requres
#::
#:: REQURES
#        pythonizer.pl
#        Pythonizer.pm
#        Softpano.pm

#--- Development History
#
# Ver      Date        Who        Modification
# ====  ==========  ========  ==============================================================
# 0.10 2019/10/09  BEZROUN   Initial implementation
# 0.20 2019/11/13  BEZROUN   Tail comment is now treated as a special case and does not produce a lexem
# 0.30 2019/11/14  BEZROUN   Parsing of literal completly reorganized.
# 0.40 2019/11/14  BEZROUN   For now double quoted string are translatied into concatenation of components
# 0.50 2019/11/15  BEZROUN   Better parsing of Perl literals implemented
# 0.60 2019/11/19  BEZROUN   Problem of translation of ` ` (and rx() is that it is Python version dependent
# 0.70 2019/11/20  BEZROUN   Problem of translation of tr/abc/def/ solved
# 0.71 2019/12/20  BEZROUN   Here strings are now processed
# 0.80 2020/02/03  BEZROUN   #\ means continuation of the statement. Allow processing multiline statements (should be inserted by perl_normalizer)
# 0.81 2020/02/03  BEZROUN   If the line does not ends with ; { or } we assume that the statement is continued on the next line
# 0.90 2020/05/16  BEZROUN   Nesting is performed from this module
# 0.91 2020/06/15  BEZROUN   Tail comments are artifically made properties of the last token in the line
# 0.92 2020/08/06  BEZROUN   gen_statement moved from pythonizer, ValCom became a local array

use v5.10;
use warnings;
use strict 'subs';
use feature 'state';
#use Pythonizer qw(correct_nest getline prolog epilog output_line);
require Exporter;

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

@ISA = qw(Exporter);
#@EXPORT = qw(tokenize  @ValClass  @ValPerl  @ValPy $TokenStr);
@EXPORT = qw(gen_statement tokenize @ValClass  @ValPerl  @ValPy $TokenStr);
#our (@ValClass,  @ValPerl,  @ValPy, $TokenStr); # those are from main::

  $VERSION = '0.9';
  #
  # types of veraiables detected during the first pass; to be implemented later
  #
  %is_numberic=();
#
# List of Perl special variables
#

   %SPECIAL_VAR=('O'=>'os.name','T'=>'OS_BASETIME', 'V'=>'sys.version[0]', 'X'=>'sys.executable()',
                 ';'=>'PERL_SUBSCRIPT_SEPARATOR','>'=>'UNIX_EUID','<'=>'UNIX_UID','('=>'os.getgid()',')'=>'os.getegid()');


   %keyword_tr=('eq'=>'==','ne'=>'!=','lt'=>'<','gt'=>'>','le'=>'<=','ge'=>'>=','x'=>' * ',
                'my'=>'','own'=>'global','local'=>'', 'state'=>'global',
                'if'=>'if ','else'=>'else: ','elsif'=>'elif ', 'unless'=>'if ', 'until'=>'until ','for'=>'for ','foreach'=>'for ',
                'last'=>'break ','next'=>'continue ','close'=>'.f.close',
                'chdir'=>'os.chdir','chmod'=>'.os.chmod','chr'=>'chr','exists'=>'.has_key','exit'=>'.sys.exit',
                'exists'=> 'in', # if  key in dictionary
                'map'=>'map','grep'=>'filter','sort'=>'sort','caller'=>'perl_caller_builtin',
                'split'=>'.split','join'=>'.join','keys'=>'.keys','localtime'=>'.localtime',
                'mkdir'=>'os.mldir','oct'=>'eval','ord'=>'ord','chomp'=>'.rstrip("\n")','chop'=>'[0:-1]',
                'length'=>'len', 'package'=>'import', 'scalar'=>'len', 'index'=>'.find','rindex'=>'.rfind', 'say'=>'print','die'=>'raise',
                'sub'=>'def','STDERR'=>'sys.stderr','SYSIN'=>'sys.stdin','system'=>'os.system','defined'=>'perl_defined',
                'use'=>'import');

       %TokenType=('x'=>'*', 'y'=>'q', 'q'=>'q','qq'=>'q','qr'=>'q','wq'=>'q','wr'=>'q','qx'=>'q','m'=>'q','s'=>'q','tr'=>'q',
                  'if'=>'c',  'while'=>'c', 'unless'=>'c', 'until'=>'c', 'for'=>'c', 'foreach'=>'c', 'given'=>'c',
                  'else'=>'C', 'elsif'=>'C','when'=>'C', 'default'=>'C','last'=>'C','next'=>'C','return'=>'C','exit'=>'C',
                  'length'=>'f','scalar'=>'f','caller'=>'f','die'=>'f',
                  'my'=>'t','own'=>'t','local'=>'t', 'state'=>'t','local'=>'t',
                  'index'=>'f', 'rindex'=>'f', 'substr'=>'f','sprintf'=>'f', 'chomp'=>'f', 'chop'=>'f','keys'=>'f','values'=>'f',
                  'chomp'=>'f','shift'=>'f','push'=>'f','pop'=>'f', 'split'=>'f','join'=>'f','exists'=>'f','defined'=>'f',
                  'chdir'=>'f','chmod'=>'f','chr'=>'f','system'=>'f',
                  'map'=>'f','grep'=>'f','sort'=>'f','mkdir'=>'f','oct'=>'f','ord'=>'f',
                  'sub'=>'k','print'=>'f','say'=>'f','read'=>'f','open'=>'f','close'=>'f','STDERR'=>'k','STDIN'=>'k',
                  'use'=>'c','package'=>'c');

#
# one to one translation of digramms. most are directly translatatble.
#
   %digram_tokens=('++'=>'^','--'=>'^','+='=>'=','-='=>'=', '.='=>'=', '%='=>'=', '=~'=>'~','!~'=>'~',
                   '=='=>'>','!='=>'>','>='=>'>','<='=>'>','<>'=>'<','=>'=>':','->'=>'.','::'=>'.',
                   '<<' => 'H', '>>'=>'=', '&&'=>'0', '||'=>'1',); #and/or/not

   %digram_map=('++'=>'+=1','--'=>'-=1','+='=>'+=', '.='=>'+=', '=~'=>'=','<>'=>'readline()','=>'=>': ','->'=>' ',
                '&&'=>' and ', '||'=>' or ','::'=>'.'); #and/or/not
my ($source,$cut,$tno)=('',0,0);
#
# Tokenize line into one string and three arrays @ValClass  @ValPerl  @ValPy
#
sub tokenize
{
my ($l,$m);
      $source=$_[0];
      $tno=0;
      @ValClass=@ValCom=@ValPerl=@ValPy=(); # "Token Type", token comment, Perl value, Py analog (if exists)
      $TokenStr='';
      if ($::debug > 3 && $main::breakpoint >= $. ){
         $DB::single = 1;
      }
      while($source) {
         if( $source=~/^(\s+)/) {
            # truncate white space on the left
            substr($source,0,length($1))='';
         }
         $s=substr($source,0,1);
         if( $s eq '#' ){
            # plain vanilla tail comment
            if( $tno > 0 ){
               $tno--;
               $ValCom[$tno]=$source;
               $source=Pythonizer::getline();
               next;
            }
            print("Internal error in scanner\n");
            $DB::single = 1;

         }elsif( $s eq ';'){
            #
            # buffering tail is possible only if banace of round bracket is zero
            # because of for($i=0; $i<@x; $i++)
            #
            $balance=0;
            for ($i=0;$i<@ValClass;$i++) {
               if ($ValClass[$i] eq '(') {
                  $balance++;
               }elsif ($ValClass[$i] eq ')') {
                  $balance--;
               }
            }
            if($balance != 0 ) {
               # for statement or similar situation
               $ValClass[$tno]=$ValPerl[$tno]=$s;
               $ValPy[$tno]=',';
               $cut=1; # we need to continue
            }else {
               # this is regular end of statement
               if( length($source) == 1 ){
                   last; # exit loop;
               }
               if( $source !~/^;\s*#/ ){
                  # there is some meaningful tail -- multiple statement on the line
                  Pythonizer::getline(substr($source,1)); # save tail that we be processed as the next line.
                  last;
               }else{
                  # comment after ; this is end of statement
                  $ValCom[-1]=substr($source,1); # comment attributed to the last token
                  $source='';
                  last;
               }
            }
        }
         # This is a meaningful symbol which tranlates into some token.
         $ValClass[$tno]=$ValPerl[$tno]=$ValPy[$tno]=$s;
         $ValCom[$tno]='';
         if( $s eq '}'){
            # we treat '}' as a separate "dummy" statement -- eauvant to ';' plus change of nest -- Aug 7, 2020
            if( $tno==0 ){
                 # we recognize it as the end of the block if '}' is the first symbol
                if( length($source)>1 ){

                   Pythonizer::getline(substr($source,1)); # save tail
                   $source=$s; # this was we artifically create line with one symbol on it;
                }
                last; # we need to prosess it as a seperate one-symbol line
            }elsif(length($source)==1) {
                # NOTE: here $tno>0 and we reached the last symbol of the line
                # we recognize it as the end of the block
                #curvy bracket as the last symbol of the line
                Pythonizer::getline('}'); # make it a separate statement
                popup(); # kill the last symbol
                last; # we truncate '}' and will process it as the next line
            }
            # this is closing bracket of hash element
            $ValClass[$tno]=')';
            $ValPy[$tno]=']';
            $cut=1;

         }elsif ($s eq '{' ){
            # we treat '{' as the beginning of the block if it is the first or the last symbol on the line or is preceeded by ')' -- Aug 7, 2020
             if( $tno==0) {
                if( length($source)>1 ){
                   Pythonizer::getline(substr($source,1)); # save tail
                }
                last; # artificially truncating the line making it one-symbol line
             }elsif( length($source)==1 || substr($source,1)=~/^\s*#/ || $ValClass[$tno-1] eq ')'  ){
                # $tno>0 this is the case when curvy bracket is the last statement on the line ot is preceded by ')'
                Pythonizer::getline($source); # make is a new line to be proceeed later
                popup();  # kill the last symbol
                last;
             }
            $ValClass[$tno]='('; # we treat anything inside curvy backets as expression
            $ValPy[$tno]='[';
            $cut=1;
         }elsif( $s eq '/' && ($tno==0 || index('~(',$ValClass[$tno-1])>-1) ){
            # slash means regex in three cases: if(/abc/){0}; $a=~/abc/; /abc/; Crazy staff
              $ValClass[$tno]='q';
              $cut=single_quoted_literal($s,1);
              $ValPerl[$tno]=substr($source,1,$cut-2);
              if (index('~>',$ValClass[$tno-1])==-1) {
                 $ValPy[$tno]='perl_default_var.re.match(r'.escape_quotes($ValPerl[$tno]).')'; #  double quotes neeed to be escaped just in case
              }else{
                 $ValPy[$tno]='.re.match(r'.escape_quotes($ValPerl[$tno]).')'; #  double quotes neeed to be escaped just in case
              }
         }elsif( $s eq "'" ){
            #simple string, but backslashes of  are allowed
            $ValClass[$tno]="'";
            $cut=single_quoted_literal($s,1);
            $ValPerl[$tno]=substr($source,1,$cut-2);
            if ($tno>0 && $ValPerl[$tno-1] eq '<<' ) {
               # my $here_str = <<'END'; -- added Dec 20, 2019
               $tno--; # overwrite previous token; Dec 20, 2019 --NNB
               $ValPy[$tno]=Pythonizer::get_here($ValPerl[$tno]);
               $cut=length($source);
            }else{
               $ValPy[$tno]="'".escape_backslash($ValPerl[$tno])."'"; # only \n \t \r, etc needs to be  escaped
            }
         }elsif( $s eq '"' ){
            $ValClass[$tno]='"';
            $cut=double_quoted_literal('"',1); # side affect populates $ValPy[$tno] and $ValPerl[$tno]
            if ($tno>0 && $ValPerl[$tno-1] eq '<<' ) {
               # my $here_str = <<'END'; -- added Dec 20, 2019
               $tno--; # overwrite previous token; Dec 20, 2019 --NNB
               $ValClass[$tno]="'";
               $ValPerl[$tno]=substr($source,1,$cut-2); # we do not allow variables is here string.
               $ValPy[$tno]=Pythonizer::get_here($ValPerl[$tno]);
               $cut=length($source);
            }
         }elsif( $s eq '`' ){
             $ValClass[$tno]='q';
             $cut=single_quoted_literal($delim,1);
             $ValPy[$tno]=$ValPerl[$tno]=substr($source,1,$cut-2); # literal without quotes is needed.
             $ValPy[$tno]='subprocess.check_output("'.$ValPerl[$tno].'")';
         }elsif( $s eq '<' && substr($source,1,1) eq '<' ){
             #my $message = <<'END_MESSAGE';
             $ValClass[$tno]='H';
             $ValPerl[$tno]='<<';
             $ValPy[$tno]='';
             $cut=2;
         }elsif( $s=~/\d/ ){
            # processing of digits should preceed \w ad \w includes digits
            if( $source=~/(\d+(?:[.e]\d+)?)/ ){
                $val=$1;
                $ToSub[$tno]='e';
            }elsif( $source=~/(0x\w+)/ ){
               # need to add octal andhexadecila later
               $val=$1;
               $ToSub[$tno]='x';
            }elsif( $source=~/(0b\d+)/ ){
               #binary
               $val=$1;
               $ToSub[$tno]='b';
            }elsif ( $source=~/(\d+)/ ){
                $val=$1;
                $ToSub[$tno]='i';
            }
            $ValClass[$tno]='d';
            $ValPy[$tno]=$ValPerl[$tno]=$val;
            $cut=length($val);
        }elsif( $s=~/\w/ ){
            $source=~/(\w+)/;
            $w=$1;
            $ValPerl[$tno]=$w;
            $cut=length($w);
            $class=(exists($TokenType{$w})) ? $TokenType{$w}:'i';
            if (exists($keyword_tr{$w})){
                $ValPy[$tno]=$keyword_tr{$w};
            }else{
                $ValPy[$tno]=$w;
            }
            $ValClass[$tno]=$class;
            if( $class eq 't' ) {
               $ValPy[$tno]='';
            }elsif( $class eq 'q' ){
               # q can be tranlated into """", but qw actually is an expression
               $delim=substr($source,length($w),1);
               if($w eq 'q') {
                  $cut=single_quoted_literal($delim,2);
                  $ValPerl[$tno]=substr($source,length($w)+1,$cut-length($w)-2);
                  $w=escape_backslash($ValPerl[$tno]);
                  $ValPy[$tno]=escape_quotes($w);
               }elsif($w eq 'qq'){
                  # decompose doublke quote populate $ValPy[$tno] as a side effect
                  $cut=double_quoted_literal($delim,length($w)+1); # side affect populates $ValPy[$tno] and $ValPerl[$tno]

               }elsif($w eq 'qx') {
                  #executable
                  if( $delim eq "'") {
                     $cut=single_quoted_literal($delim,length($w)+1);
                     $ValPerl[$tno]=substr($source,length($w)+1,$cut-length($w));
                     $ValPy[$tno]='system("'.$ValPy[$tno].'")';
                  }else{
                     $cut=double_quoted_literal($delim,length($w)+1);
                  }
                }elsif($w eq 'm' | $w eq 'qr') {
                  #executable
                   $cut=single_quoted_literal($delim,length($w)+1);
                   $ValPerl[$tno]=substr($source,length($w)+1,$cut-length($w)-2);
                   $ValPy[$tno]='.re.match(r"'.$ValPerl[$tno].'")';
                }elsif($w eq 'tr' || $w eq 'y' || $w eq  's' ){
                  # tr function has two parts; also can be named y
                  $cut=single_quoted_literal($delim,length($w)+1);
                  $arg1=substr($source,length($w)+1,$cut-length($w)-2);
                  if( substr($source,$cut,1) eq $delim && index('{([<',$delim) == -1 ){
                     $arg2='';
                     $cut++;
                  }else{
                     if( index('{([<',$delim) > -1 ){
                        $delim=substr($source,$cut,1);
                        $cut2=single_quoted_literal($delim,$cut+1);
                        $arg2=substr($source,$cut+1,$cut2-$cut-2);
                     }else{
                        $cut2=single_quoted_literal($delim,$cut);
                        $arg2=substr($source,$cut,$cut2-$cut-1);
                     }
                     $cut=$cut2;
                   }
                   if( $w eq 'tr' ){
                       $ValClass[$tno]='f';
                       $ValPerl[$tno]='tr';
                       $ValPy[$tno]="maketrans('$arg1','$arg2')"; # needs to be translated into  two statements
                   }else{
                       $ValClass[$tno]='f';
                       $ValPerl[$tno]='m';
                       $ValPy[$tno]=".re.sub(r'$arg1',r'$arg2')";
                   }

               }elsif($w eq 'qw') {
                   $cut=single_quoted_literal($delim,length($w)+1);
                   $ValPerl[$tno]=substr($source,length($w)+1,$cut-length($w)-2);
                   if ($ValPerl[0] eq 'use') {
                      $ValPy[$tno]=$ValPerl[$tno];
                   }else{
                      $ValPy[$tno]='"'.$ValPerl[$tno].'".split(r"\s+")';
                   }
               }
           }
         }elsif( $s eq '$' ){
            $s2=substr($source,1,1);
            $ValClass[$tno]='s';
            if( $s2 eq '.' ){
               # file line number
                $ValPy[$tno]='lineno';
                $cut=2;
            }elsif( $s2 eq '^' ){
                $s3=substr($source,2,1);
                $cut=3;
                if ($s3=~/\w/ ){
                   if (exists($SPECIAL_VAR{$s3})) {
                     $ValPy[$tno]=$SPECIAL_VAR{$s3};
                   }else{
                     $ValPy[$tno]='perl_special_var_'.$s3;
                  }
                }
            }elsif( index(';<>()',$s2) > -1 ){
               $ValPy[$tno]=$SPECIAL_VAR{$s2};
               $cut=2;
            }elsif( $s2 =~ /\d/ ) {
                $source=~/^.(\d+)/;
                $ValClass[$tno]='s'; #scalar
                $ValPerl[$tno]=$1;
                if( $s2 eq '0' ) {
                  $ValPy[$tno]="sys.argv[0]";
                }else{
                   $ValPy[$tno]="rematch.group($1)";
                }
                $cut=length($1)+1;
            }elsif( $s2 eq '#') {
               $source=~/^..(\w+)/;
               $ValClass[$tno]='s';
               $ValPerl[$tno]=$1;
               $ValPy[$tno]='len($1)';
               $cut=length($1)+2;
            }elsif( $s2 eq '$'){
               $source=~/^..(\w+)/;
               $ValClass[$tno]='p';
               $ValPerl[$tno]=$1;
               $ValPy[$tno]='addr($1)';
               $cut=length($1)+2;
            }elsif( $source=~/^.(\w+)/) {
               $ValClass[$tno]='s'; #scalar
               $ValPy[$tno]=$ValPerl[$tno]=$1;
               $cut=length($1)+1;
               if (length($1) ==1 ) {
                  $s2=$1;
                  if ($s2 eq '_') {
                     if( $source=~/^(._\s*\[\s*(\d+)\s*\])/ ){
                        $ValPy[$tno]='perl_arg_array['.$2.']';
                        $cut=length($1);
                     }else{
                        $ValPy[$tno]='perl_default_var';
                        $cut=2;
                     }
                  }elsif ($s2 eq 'a' || $s2 eq 'b' ) {
                     $ValPy[$tno]='perl_sort_'.$s2;
                     $cut=2;
                  }
               }elsif( $1 eq 'ENV' ){
                 $ValPy[$tno]='os.environ';
               }

            }elsif($source=~/^.(\w+(?:\:\:\w+)+)/ ){
               $var=$1;
               $ValPerl[$tno]=$1;
               $var =~ tr/:/_/;
               $ValPy[$tno]="Imported_$var";
               $cut=length($1)+1;
            }
         }elsif( $s eq '@' ){
            $source=~/^.(\w+)/;
            if ($1 eq '_') {
               $ValPy[$tno]="perl_arg_array";
            }
            $ValClass[$tno]='a'; #array
            $ValPerl[$tno]=$1;
            $ValPy[$tno]=$1;
            $cut=length($1)+1;
         }elsif( $s eq '%' ){
            $source=~/^.(\w+)/;
            $ValClass[$tno]='h'; #hash
            $ValPerl[$tno]=$1;
            $ValPy[$tno]=$1;
            $cut=length($1)+1;

         }elsif( $s eq '[' ){
            $ValClass[$tno]='('; # we treat anything inside curvy backets as expression
            $cut=1;
         }elsif( $s eq ']' ){
            $ValClass[$tno]=')'; # we treat anything inside curvy backets as expression
            $cut=1;
         }elsif( $s=~/\W/ ){
            #This is delimiter
            $digram=substr($source,0,2);
            if( exists($digram_tokens{$digram}) ){
               $ValPerl[$tno]=$digram;
               $ValClass[$tno]=$digram_tokens{$digram};
               if( exists($digram_map{$digram}) ){
                  $ValPy[$tno]=$digram_map{$digram}; # changes for Python
               }else{
                  $ValPy[$tno]=$ValPerl[$tno]; # same as in Perl
               }
               $cut=2;
            }else{
               $ValClass[$tno]=$ValPerl[$tno]=$ValPy[$tno]=$s;
               if( $s eq '.' ){
                  $ValPy[$tno]=' + ';
               }elsif($s eq '<' ){
                  $ValClass[$tno]='>';
               }
               $cut=1;
            }
         }
         substr($source,0,$cut)='';
         if( length($source)==0 ) {
             # the current line ended by ; of { } was not reached
             $source=Pythonizer::getline();
         }
         if( $::debug > 3 ){
            say STDERR "Lexem $tno Current token='$ValClass[$tno]' value='$ValPy[$tno]'", " Tokenstr |",join('',@ValClass),"| translated: ",join(' ',@ValPy);
         }
         $tno++;
      } # while

      $TokenStr=join('',@ValClass);
      $num=sprintf('%4u',$.);
      ($::debug>2) && say STDERR "\nLine $num. \$TokenStr: =|",$TokenStr, "|= \@ValPy: ",join(' ',@ValPy);

} #tokenize

sub popup
{
    pop(@ValClass);
    pop(@$ValPerl);
    pop(@ValPy);
    pop(@ValCom);
}
sub single_quoted_literal
# A backslash represents a backslash unless followed by the delimiter or another backslash,
# in which case the delimiter or backslash is interpolated.
{
($closing_delim,$offset)=@_;
my ($m,$sym);
# The problem is decomposting single quotes string is that for brackets closing delimiter is different from opening
# The second problem is that \n in single quoted string in Perl means two symbols and in Python a single symbol (newline)
      $closing_delim=~tr/{[(</}])>/;
      #simple string, but osnmebacklashes are allowed
      for($m=$offset; $m<=length($source); $m++) {
         $sym=substr($source,$m,1);
         last if ($sym eq $closing_delim && substr($source,$m-1,1) ne '\\' );
      }
      return $m+1; # this is first symbol after closing quote
}
#
# Returns cut
# As a side efecct populates $ValPerl[$tno] $ValPy[$tno]
sub double_quoted_literal
{
($closing_delim,$offset)=@_;
my ($k,$quote,$close_pos,$ind,$result,$prefix);
   $closing_delim=~tr/{[(</}])>/;
   $close_pos=single_quoted_literal($closing_delim,$offset); # first position after quote
   $quote=substr($source,$offset,$close_pos-1-$offset); # extract literal
   $ValPerl[$tno]="$_[0]$quote$closing_delim";
   #
   # decompose all scalar variables, if any, Array and hashes are left "as is"
   #
   $k=index($quote,'$');
   if ($k==-1) {
      # double quotes are used for a simple literal that does not reaure interpolation
      # Python equvalence between single and doble quotes alows some flexibility
      $ValPy[$tno]=escape_quotes($quote);
      return $close_pos;
   }
   while( $k > -1 ){
      if( $k > 0 ){
         $result.=escape_quotes(substr($quote,0,$k)).' + '; # add literal part of the string
      }
      $quote=substr($quote,$k+1);
      if( $quote=~/(\w+)([\[\{].+[\]\}])?/ ){
         #element of the array of hash
         $ind=$2;
         $cut=length($1);
         if (defined($ind)) {
            $cut+=length($ind);
            $ind =~ tr/$//d;
         }else {
            $ind='';
         }
         if( $1=~/\d+/ || exists($is_numberic{$1}) ){
            # Generally you should use table of types here
            $result.='str('.$1.$ind.')'; # add numberic Variable part of the string
         }else{
            $result.=$1.$ind; # add string Variable part of the string
         }
         $quote=substr($quote,$cut);
         if( length($quote)>0 ) {
            $result.=' + '; # we will add at least one chunk
         }
     }else{
         say "Error in translation";
         last;
      }
      $k=index($quote,'$');
   }
   if( length($quote)>0 ){
       $result.=escape_quotes($quote);
   }
   $ValPy[$tno]=$result;
   return $close_pos;
}
sub escape_quotes
{
my $string=$_[0];
my $delim='"';
   if (scalar(@_)>1) {
      $delim=$_[1];
   }
my $result;
   if (index($string,'"')==-1 ) {
      $result.=q(").$string.qq("); # closing quote in the last chank if it exist.
   }elsif(index($string,"'")==-1 ) {
      $result.=qq(').$string.qq('); # closing quote in the last chank if it exist.
   }else{
     $result=$string;
     for( my $i=length($string); $i>=0; $i-- ){
        if (substr($string,$i,1) eq $delim ) {
           substr($result,$i,0)='\\';
        }
     } # for
     $result=$delim.$result.$delim;
   }
   return $result;
}
sub escape_backslash
# All special symbols different from the delimiter and \ should be escaped when translating Perl single quoted literal to Python
# For example \n \t \r  are not treated as special symbols in single quotes in Perl (which is probably a mistake)
{
my $string=$_[0];
my $backslash='\\';
my $result=$string;
   for( my $i=length($string)-1; $i>=0; $i-- ){
      if (substr($string,$i,1) eq $backslash) {
         if(index('nrtfbvae',substr($string,$i+1,1))>-1 ) {
            substr($result,$i,0)='\\'; # this is a really crazy nuance
         }
      }
   } # for
   return $result;
}

sub gen_statement
{
my $i;
my $line='';
   if( $::FailedTrans && scalar(@ValPy)>0 ){
      $line=$ValPy[0];
      for( $i=1; $i<@ValPy; $i++ ){
         next unless(defined($ValPy[$i]));
         next if ($ValPy[$i] eq '');
         $s=substr($ValPy[$i],0,1);
         if( $ValPy[$i-1]=~/\w$/) {
            if( index(q('"/),$s)>-1 || $s=~/\w/ ){
                # print "something" if /abc/
                $line.=' '.$ValPy[$i];
            }else{
                $line.=$ValPy[$i];
            }
         }else {
            $line.=$ValPy[$i];
         }
      }
      ($line) && Pythonizer::output_line($line,' #FAILTRAN');
   }elsif( scalar(@::PythonCode)>0 ){
      $line=$::PythonCode[0];
      for( my $i=1; $i<@::PythonCode; $i++ ){
         next unless(defined($::PythonCode[$i]));
         next if ($::PythonCode[$i] eq '');
         $s=substr($::PythonCode[$i],0,1); # the first symbol
         if( substr($line,-1,1)=~/[\w'"]/ &&  $s =~/[\w'"]/ ){
            # space between identifiers and before quotes
            $line.=' '.$::PythonCode[$i];
         }else{
            #no space befor delimiter
            $line.=$::PythonCode[$i];
         }


      } # for
      if( defined[$ValCom[-1]] && length($ValCom[-1]) > 0  ){
         # that means that you need a new line. bezroun Feb 3, 2020
         Pythonizer::output_line($line,$ValCom[-1] );
      }else{
        Pythonizer::output_line($line);
      }
      for ($i=1; $i<$#ValCom; $i++) {
          if( defined($ValCom[$i]) && length($ValCom[$i])>0 ){
             # NOTE: This is done because comment can be in a wrong position due to Python during generation and the correct placement  is problemtic
             Pythonizer::output_line('',$ValCom[$i] );
          }  # if defined
      }
   }elsif($line){
       Pythonizer::output_line('','#NOTRANS: '.$line);
   }
   if( $::FailedTrans && $debug ){
      out("\nTokens: $TokenStr ValPy: ".join(' '.@::PythonCode));
   }
#
# Prepare for the next line generation
#
   Pythonizer::correct_nest(); # equalize CurNest and NextNest;
   @::PythonCode=();
   return;
}
1;