package Library::Simple;
use Library::Thesaurus;

require 5.005_62;
use strict;
use warnings;
use XML::DT;
use DB_File;
use Fcntl ;
use CGI qw/:standard/;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw( &mkdiglib );
our @EXPORT = qw( );
our $VERSION = '0.01';

sub navigate {
  my ($self,%args) = @_;

  my $html = "";

  $html .= $self->{the}->navigate({expand => [ 'HAS','NT','INST' ]},%args);

  my @terms = (defined($args{t})?
	       $self->{the}->tc($args{t},'BT','POF','IOF'):
	       ());

  $html .= start_form('POST');
  $html .= "procurar ". textfield('p'). "em ";
  $html .= popup_menu('t', [ @terms ]);
  $html .= submit(" Procurar "), end_form;
  $html .= "<br><br>";

  if ($args{all} || (defined($args{t}) &&  uc($args{t}) ne uc($self->{the}->top_name))) {
    if (defined($args{p})) {
      $html .= $self->f4($args{p},$args{t});
    } else {
      $html .= $self->f1($args{t});
    }
  } else {
    if (defined($args{p})) {
      $html .= $self->f3($args{p});
    } else {
      #...
    }
  }


  $html;
}

sub mkdiglib{
 my $userconf = shift;
 my $i;

  my $the=thesaurusLoad("$userconf->{thesaurus}");
  $the->storeOn("$userconf->{name}.thesaurus.store");

 my @a = &{$userconf->{catsyn}{1}}($userconf->{catfile});
 open(H1,">$userconf->{name}.indextt");
 open(H2,">$userconf->{name}.indextext");
 my %h;
 tie %h, "DB_File", "$userconf->{name}.indexhtml",
         O_RDWR|O_CREAT, 0644, $DB_BTREE or die $!;

 my %h2;
 tie %h2, "DB_File", "$userconf->{name}.indextt2", 
         O_RDWR|O_CREAT, 0644, $DB_BTREE or die $!;

 for(@a)
  { $i++;
    print ".";
    $h{$i}= &{$userconf->{catsyn}{3}}($_) ;
    print H1 "\n$i:", join(" / ", &{$userconf->{catsyn}{2}}($_)) ;
    for( &{$userconf->{catsyn}{2}}($_)) {$h2{$_} .= "$i|" ;}
    print H2 "\n$i:", &{$userconf->{catsyn}{4}}($_) ;
  }

 close H1;
 close H2;
 untie %h;
 open(H,">$userconf->{name}.indextt2.keys");
 open(H1,">$userconf->{name}.indextt2.statistics");
 for(keys %h2){
   my  $howmany = $h2{$_} ;
   $howmany =~ s/\d//g;
   print H "\n$_";
   print H1 "\n$_:", length($howmany);
 }
 close H1;
 close H;
 untie %h2;
}

sub opendiglib{
 my $cf=shift;
 my %h;
 tie %h, "DB_File", "$cf->{name}.indexhtml", O_RDONLY, 0644, $DB_BTREE or die $!;
 my %h2;
 tie %h2, "DB_File", "$cf->{name}.indextt2", O_RDONLY, 0644, $DB_BTREE or die $!;
 bless {name=> $cf->{name},
        the => thesaurusRetrieve("$cf->{name}.thesaurus.store"),
        db  => \%h,
        tt2 => \%h2
       }
}

sub f1{
  my ($self,$tt)=@_; 
  orf1($self, $self->{the}->tc($tt,"NT","UF","INST") )
}

sub orf1{
  my $self=shift;
  htmlofids($self,tt2ids($self,@_))
}

sub f3{
  my ($self,$er)=@_;
  htmlofids($self,grepcut1("$self->{name}.indextext",$er));
}

sub f4{
  my ($self,$er, $tt)=@_;
  my @r1 =grepcut1("$self->{name}.indextext",$er);
  my @r2 =tt2ids($self,$tt);
  #  print join(":",@r1), "\n\n\n",join(":",@r2);

  htmlofids($self, (inter(\@r1,\@r2)));
}

sub inter{
 my ($l1,$l2)=@_;
 my %h;
 @h{@$l1} = @$l1;
 grep {defined ($_)} @h{@$l2};
}

sub tt2ids{
  my ($self,@tt)=@_;
  my @a=();
  my %a=();
  for my $tt(@tt){
     for(grepcut1("$self->{name}.indextt2.keys",$tt)){
        push(@a ,(split('\|',$self->{tt2}{$_})));
        pop(@a);
     }
  }
  @a{@a}=@a;
  (keys %a);
}

sub grepcut1{
  my ($f,$er)=@_; 
  open F, "$f" or die;
  my @r = ();
  while(<F>){ push(@r,$1) if /$er/i && /^(.*?)[:\n]/; }
  close F;
  @r       
}

sub htmlofids{
  my $self=shift;
  join("\n",(map {$self->{db}{$_} || "<!--\n.................$_ -->\n" } @_));
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Library - Perl extension for Digital Library support

=head1 SYNOPSIS

  use Library;

  $a = mkdiglib($conf)

=head1 DESCRIPTION


Library is a module for managing a digital library. It is composed of
three other modules named news, catalog and thesaurus. You can read
the documentation for each of them in the corresponding pod file.  To
use this module there is only the need of using Library::Thesaurus.
The other two modules are totally optional.

The main purpose of this module is to maintain the relation between
one or more catalogs and a thesaurus. While we need that the user
define a thesaurus and process it with the Library::Thesaurus module,
the catalog can be implemented in any way the user wants.

To this be possible, it should be some way to access any kind of
catalog: a plain text file, XML document, SQL database or anything
else. The only method possible is to define functions to convert these
implementation techniques into a mathematical definition. So, the user
should give four functions to this module to it be capable of use the
catalog. These functions are:

=over 4

=item 1

Given a string (say, a catalog identifier) the function should return
a Perl array with all catalog entries. This array should be the same
everytime the function is called for the same catalog to maintain some
type of indexing. The function can use this string as a filename, a
SQL table identifier or anything else the function can understand.

=item 2

Given an entry with the format returned by the previous function, this
function should return a list of terms related to the object
catalogued by this entry. These terms will be used latter for
thesaurus integration.

=item 3

Given an entry, return a piece of HTML code to be embebed when listing
records.

=item 4

Given an entry, return the searchable text it includes.

=back

The following example shows a sample configuration:

  $userconf = {
    catfile   => '/var/library/catalog',
    thesaurus => '/var/library/thesaurus',
    name => 'library name',
    catsyn  => {
       1 => sub{ my $file=shift;
                 my $t=`cat $file`;
                 return ($t =~ m{(<entry.*?</entry>)}gs); },
     2 => sub{ ay $f=shift;
               my @r=();
               while($f =~ m{<rel\s+tipo='(.*?)'>(.*?)</rel>}g)
                  { push @r, $2; }
               @r; },
     3 => sub{ my $f=shift; &mp::cat::fichacat2html($f)},
     4 => sub{ my $f=shift;
               $f =~ s{</?\w+}{ }g;
               $f =~ s/(\s*[\n>"'])+\s*/,/g;
               $f =~ s/\w+=//g;
               $f =~ s/\s{2,}/ /g;
               $f }  }  };

When using the C<mkdiglib> function with this configuration
information, the module will create a set of files with cached
data for quick response. This function returns a Library object.

After creating the object, we can open it on another script with
the C<opendiglib> command wich receives the base name of the digital
library. The base name is the path where it was created concatenated
with the identifier used.

To consult these object, one can use some of the following methods:

=over 4

=item 1

Given a thesaurus term, return a HTML string with the catalog entries
related to the term. It is used a transitive closure in a way that some
entries without that term will be matched because they contain a term
wich is related with the searched one.

=item 2

The same thing as the above but for more than one term.

=item 3

Given a regular expression, return the HTML corresponding with the
matched entries.

=item 4

This is a mix of 1 with 3. Given a term and regular expression, return
the intersection result.

=back



=head1 AUTHOR

José João Almeida   <jj@di.uminho.pt>

Alberto Simões      <albie@alfarrabio.di.uminho.pt>

=head1 SEE ALSO

perl(1).

=cut

