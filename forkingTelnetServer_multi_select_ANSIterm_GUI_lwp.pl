#!c:\perl\bin\perl
#####
# (C) Marc Labelle 2010
#


use strict;
no strict "subs";
use threads;
use threads::shared;
#use strict;
use Term::ReadKey;
use Time::HiRes qw( usleep );
use Switch;
use Net::Server::Fork;
#use MSL::TELNET::TEST;
use Win32::Console::ANSI;
use Term::ANSIColor;
use Term::ANSIScreen qw/:color :cursor :screen/;
use Time::HiRes qw( usleep );
use IO::Select;
no strict "vars";
@ISA = qw(Net::Server::Fork);
use strict "vars";
use Data::Dumper;
use LWP::UserAgent;
use HTML::LinkExtor;
use URI::URL;
use File::Path qw(mkpath);

$|=1;
our %test_Postoffice :shared;
our @URL_Dispatch_FIFO :shared =();
our $URL_Dispatch_FIFO_ptr :shared =\@URL_Dispatch_FIFO;
{
	my $scrExecThr = threads->create(\&thrExecURLsequencer,$URL_Dispatch_FIFO_ptr,2);
	$scrExecThr->detach();
}


our @globalDisplayCoords=(80,25);

sub process_request {
	srand();
	my @local_box :shared =('welcome to the network');
	my $self = shift;
	my $prop = $self->{server};  
	### handle udp packets (udp echo server)
	if( $prop->{udp_true} ){
		if( $prop->{udp_data} =~ /dump/ ){
			require Data::Dumper;
			$prop->{client}->send( Data::Dumper::Dumper( $self ) , 0);
		}else{
			$prop->{client}->send("You said \"$prop->{udp_data}\"", 0 );
		}
		return;
	}
	### handle tcp connections (tcp echo server)
	print color 'reset';
	print "Welcome to Marc's Test Telnet Server running on port $$\r\nserver> ";
	my $registered=0;
	my $POBoxKey;
	while (!$registered) {
		my $_key=int(rand(16384));
		#register PO Box in postoffice
		unless (exists($test_Postoffice{$_key})) {$POBoxKey=$_key;$test_Postoffice{$POBoxKey}=\@local_box;push(@local_box, "registered in postoffice: $POBoxKey");$registered=1;}		
	}
	print "telnet> ";

	### eval block needed to prevent DoS by using timeout
	my $timeout = 10; # give the user 30 seconds to type a line
	my $previous_alarm = alarm($timeout);
	eval {

		#local $SIG{ALRM} = sub { warn "Timed Out!\n" };
		local $SIG{ALRM} = sub {  };
		my $active = 1;
		my $chatMode=0;
		my @userCreds=('',0);
		my $Authenticated=0;
		my $userName='';
		my $selectStdIn=IO::Select->new();
		$selectStdIn->add(\*STDIN);
		my @screenBuffer=();
		my $screenBufferPtr=\@screenBuffer;
		&guiDrawCleanBox;
		guiPrintPrompt('telnet>');
		my $tempCounterInfo=0;
		while(1){	#new shiney GUI mode
			my $uInput='';
			if (scalar(@local_box)) {
				#locate 1,2;
				#print "there are messages";
				$tempCounterInfo++;
				push (@$screenBufferPtr,@local_box);
				@local_box=();
				guiPrintMessageQueueToResponseBox(@$screenBufferPtr);
				if ($chatMode)	{guiPrintPrompt('chat>');}
				else			{guiPrintPrompt('telnet>');}
			}
			#else { locate 1,2; print "==================";}
			if($selectStdIn->can_read(.1)){$uInput=<STDIN>;}
			else {usleep(1000);next;}
			my $query=parseUserIn($uInput);
			#print "DEBUG: " . scalar(@local_box) . " messages in queue\r\n";
			unless ($query eq '') {
				#print "server> ";
				$self->log(5,$query); # very verbose log
				unless ($chatMode) {
					switch(lc($query)){
						case	['login','logout']			{$userCreds[1]=login($screenBufferPtr, lc($query) , \$userCreds[0]);	}
						#case	'?'							{print "Commands are:\r\nget <varname>, dump, send <message>, foo, bye, launch\r\n";}
						#case	/get (\w+)/					{$query=~/get (\w+)/; print "$1: $self->{server}->{$1}\r\n";	}
						case	'dump'						{require Data::Dumper;print Data::Dumper::Dumper( $self );		}
						#case	'launch'					{launchControl(\@userCreds,\@screenBuffer);}
						case	/^send /					{$query=~s/^send //; foreach my $key (keys(%test_Postoffice)) {push(@{$test_Postoffice{$key}},$self->{server}->{'peeraddr'} . '> ' .$query);};	}#print "DEBUG: $key\r\n"; 
						case	['quit','bye','exit']		{print "session terminated by client\r\n";$active=0;			}
						#case	['foo','bar','baz']			{print "foo bar or baz was submitted\r\n";						}
						case	'game'						{playGamesGui(\@userCreds,$screenBufferPtr);push(@$screenBufferPtr, "SERVER> I hope you enjoyed your game");		}
						case	'test'						{dispatchHandlerTest(\@userCreds,$screenBufferPtr);}
						#case	/^ptf/						{if($userCreds[1]){open(FH,">>$userCreds[0].txt");$query=~s/^ptf //i;print FH $query . "\n";close(FH);} else {print "SERVER> This action requires you to be logged in\r\n";}}
						#case	'countdisplay'				{countDisplay();}
						case	'testguimode'				{enterTestGuiMode($selectStdIn);}
						case	'refresh'					{&guiClearScreen;&guiDrawCleanBox;}
						case	'chatmode'					{$chatMode=1;}
						case	/^addurl /					{$query=~s/^addurl //;push(@$URL_Dispatch_FIFO_ptr,$query);}
						else								{push(@$screenBufferPtr,'Invalid command');}
					}
				}
				else{	#in chat mode
					if ($query =~ /^\\/) {	#the query starts with an escape, thus it's a command
						$query =~s/^\\//;
						switch(lc($query)){
							case	'exit'		{$chatMode=0;}#exit chat mode
						}
					}
					else{	#normal chat
						foreach my $key (keys(%test_Postoffice)) {push(@{$test_Postoffice{$key}},$self->{server}->{'peeraddr'} . '> ' .$query);}
					}
				}
			}
			guiPrintMessageQueueToResponseBox(@$screenBufferPtr);
			if ($chatMode)	{guiPrintPrompt('chat>');}
			else			{guiPrintPrompt('telnet>');}
			unless ($active) {last;}
			usleep(1000);
			alarm($timeout);
		}

	};
	undef($test_Postoffice{$POBoxKey});
	alarm($previous_alarm);

	if ($@ eq "Timed Out!\n") {
		print STDOUT "Timed Out.\r\n";
		return;
	}

}
__PACKAGE__->run(port=>23);



############################
##
##		UI Handlers
##
sub parseUserIn{
	my $UI=$_[0];
	$UI=~s/\r?\n$//;
	if ($UI eq '') {print "\r\nCtrl-C detected, exiting...\r\n";exit(0);}
	my @UI=split(//,$UI);
	my @out=();
	foreach my $val (@UI){
		if($val eq "\b")	{pop(@out);			}
		else				{push(@out,$val);	}
	}
	return (join('',@out));

}
sub getUserIn{
	my $UI=<STDIN>;
	return(parseUserIn($UI));
}

############################
##
##	Test Handlers
##
sub testQueuePointer{
	my $queuePointer=$_[0];
	for (my $i=0;$i<10 ;$i++) {
		push (@{$queuePointer},'this is a test entry ' . $i);
	}
	return (0);
}
############################
##
##	Command Handlers
##
sub launchControl{
	my @userCreds=@{$_[0]};
	if ($userCreds[1]) {
		print "\r\nLAUNCHPAD> Which application would you like to launch:\r\n";
		print "\t1) Launch Proxy Server on \\\\mslabell-desk on port 8088\r\n";
		print "\t2) Test Application (inactive)\r\nUSER> ";
		my $input=getUserIn();
		switch ($input){
			case	'1'	{eval{system('start proxy8080to80.pl')};  if($@){print "$@"; return(0);}}
			case	'2'	{print "INACTIVE SELECTION\r\n";}
			else		{print "LAUNCHPAD> Invalid selection\r\n";return(0);}
		}
	}
	else {
		my $color='bold white on_red';
		print colored [$color],"LAUNCHPAD>";print " Launch Control is disabled for annonymous users, please login first.\r\n";
		return(0);
	}
	print "LAUNCHPAD> Done.\r\n";
	return(1);
}

#sub naught {
#		my $color='white on_black';
#		my $string;
#		switch (lc(my $colorCode)){
#			case "kw" {$color='black on_white';}#color 'black on_white'; &clline;}
#			case "uw" {$color='bold blue on_white';}#color 'blue on_white'; &clline;}
#			case "wr" {$color='bold white on_red';}#color 'white on_red'; &clline;}
#			case "c" {$color='bold cyan';}#color 'blue'; &clline;}
#			case "r" {$color='bold red';}#color 'red'; &clline;}
#			case "w" {$color='bold white';}#color 'white'; &clline;}
#			case "y" {$color='bold yellow';}#color 'yellow'; &clline;}
#			case "g" {$color='bold green';}#color 'green'; &clline;}
#			case "wu" {$color='bold white on_blue';}#color 'white on blue'; &clline;}
#		}
#		print colored [$color],"$string";
#
#}

#################
##
##	Shell Display Utilities
##
sub guiPrint{
	my $pointer=pop(@_);
	push (@$pointer,@_);
	guiPrintMessageQueueToResponseBox(@$pointer);
	return(1);
}
sub guiPrintMessageQueueToResponseBox {
	my @localMessageQueueCopy=reverse(@_);
#	my @localMessageQueueCopy=reverse(@{$messageQueuePtr});
#	my @localMessageQueueCopy=@{$messageQueuePtr};
	my @listQueue;
	#my $disPlayQueueDepth=0;
	my $maxLineLength=78;
	my $maxLineCount=20;
	# x = 78, y = 20;
	foreach my $message (@localMessageQueueCopy) {
		if (0){  #(length($message > $maxLineLength)) {	#this will need to split the message properly and reverse the split into the listQueue buffer so when teh main buffer is reversed to print onto the display the per-message size is correct
			#remember to bounds check the split line to ensure it can all fit in the remaining buffer length, else space pad the array so it will fill and exit. (or just last it here too :-/ :: no don't do this or the allignment will be funny)
		}
		else {
			push(@listQueue,$message);
		}
		if (scalar(@listQueue) >= $maxLineCount ) {last;}
	}
	while (scalar(@listQueue) < $maxLineCount ) {push (@listQueue, ' ');}
	#@listQueue=reverse(@listQueue);
	return(guiPrintArrayToResponseBox(@listQueue));


}
sub guiPrintArrayToResponseBox{
	&guiClearResponseBox;
	#my @array=reverse(@_);
	for (my $i=2;$i<22 ;$i++) {
		locate $i,2;
		print pop(@_);
	}
	locate 1,1;
	return(1,1)
}
sub guiPrintPrompt{
	&guiClearEntryBox;
	locate 23,2;
	print "$_[0]";
	locate 23,(length($_[0]) + 3);
	return (23,(length($_[0]) + 3));
}
sub GetWindowDims{
	my @windowCoordinatePoints;

}
sub guiClearEntryBox{
	locate 23,2;
	print "                                                                              ";
	locate 23,2;
	return(23,2);
}
sub guiClearResponseBox{
	locate 2,2;
	for (my $i=2;$i<22 ;$i++) {
		locate $i,2;print "                                                                              ";
	}
	locate 2,2;
	return(2,2);
}
sub guiClearScreen{
	locate 1,1;
	for (my $i=1;$i<25 ;$i++) {
		print "                                                                                \r\n";
	}
	locate 1,1;
	return(1,1);
}
sub guiDrawCleanBox{
	my @topLineBox=();
	my @dividerLineBox=();
	my @bottomLineBox=();

	push (@topLineBox,201);
	for (my $i=0;$i<78 ;$i++) {push (@topLineBox,205);}
	push (@topLineBox,187);

	push (@dividerLineBox,199);
	for (my $i=0;$i<78 ;$i++) {push (@dividerLineBox,196);}
	push (@dividerLineBox,182);

	push (@bottomLineBox,200);
	for (my $i=0;$i<78 ;$i++) {push (@bottomLineBox,205);}
	push (@bottomLineBox,188);
	&guiClearScreen;
	locate 1,1;
	foreach(@topLineBox)	{printf ("%c",$_);}
	locate 22,1;
	foreach(@dividerLineBox){printf ("%c",$_);}
	locate 24,1;
	foreach(@bottomLineBox)	{printf ("%c",$_);}
	locate 23,1;printf ("%c",186);
	locate 23,80;printf ("%c",186);
	for (my $i=2;$i<22 ;$i++) {
		locate $i,1;
		printf ("%c",186);
		locate $i,80;
		printf ("%c",186);
	}
	locate 23,2;
	return(23,2);
}
sub enterTestGuiMode{
	my $selectStdIn=$_[0];
	&guiDrawCleanBox;
	locate 5,5;print "@ this is 5,5 press enter to continue (re-draw)";
	my $foo=<STDIN>;
	&guiClearResponseBox;
	locate 23,2;print "@ this is 23,2 press enter to continue (re-draw)";
	$foo=<STDIN>;
	&guiClearEntryBox;
	locate 23,2;
	print "this is a long draw to fill the text entry space 12345678901234567890123456789";
	locate 5,5;print "press enter to continue (re-draw only entry space)";
	$foo=<STDIN>;
	&guiClearEntryBox;
	for (my $i=2;$i<22 ;$i++) {
		locate $i,2;
		print "123456789012345678901234567890123456789012345678901234567890123456789012345678";
	}
	locate 23,3;print "Response space should be count filled.  press enter to clear";
	$foo=<STDIN>;
	&guiClearResponseBox;

	my $timer=time;
	while (time-$timer < 5) {
		locate 10,10;
		print colored [red], "this is colored just for kevin";
		usleep(3000);
		locate 10,10;
		print colored [blue],"this is colored just for kevin";
		usleep(3000);
		locate 10,10;
		print colored [green],"this is colored just for kevin";
		usleep(3000);
		locate 10,10;
		print colored [yellow],"this is colored just for kevin";
		usleep(3000);
		locate 10,10;
		print colored [white],"this is colored just for kevin";
		usleep(3000);
	}

	locate 11,3;
	print "Test print short response queue to message box.  Press enter to continue";
	$foo=<STDIN>;
	my @testMessageQueue=(	'newest message',
						'message1',
						'message2',
						'message3',
						'message4',
						'message5',
						'message6',
						'message7',
						'message8',
						'message9',
						'message0',
						'oldest message');
	guiPrintMessageQueueToResponseBox(\@testMessageQueue);
	locate 23,3;
	print "Test print long response queue to message box.  Press enter to continue";
	$foo=<STDIN>;
	@testMessageQueue=(	'newest message',
						'message1',
						'message2',
						'message3',
						'message4',
						'message5',
						'message6',
						'message7',
						'message8',
						'message9',
						'message0',
						'message1',
						'message2',
						'message3',
						'message4',
						'message5',
						'message6',
						'message7',
						'message8',
						'message9',
						'message0',
						'message1',
						'message2',
						'message3',
						'message4',
						'message5',
						'message6',
						'message7',
						'message8',
						'message9',
						'message0',
						'oldest message');
	guiPrintMessageQueueToResponseBox(\@testMessageQueue);
	&guiClearEntryBox;
	locate 23,3;print"test done press enter to continue";
	$foo=<STDIN>;

	return(0);

}
sub _enterTestGuiMode{
	my ($a_POBox,$h_postOfficePtr)=@_;
#	@globalDisplayCoords;
	#foreach(@ary){printf ("%c",$_);}
	my @topLineBox=();
	my @dividerLineBox=();
	my @bottomLineBox=();
#	for (my $i=0;$i<26 ;$i++) {
#		print "\r\n";
#	}
	&clearScreen;
	push (@topLineBox,201);
	for (my $i=0;$i<78 ;$i++) {push (@topLineBox,205);}
	push (@topLineBox,187);

	push (@dividerLineBox,199);
	for (my $i=0;$i<78 ;$i++) {push (@dividerLineBox,196);}
	push (@dividerLineBox,182);

	push (@bottomLineBox,200);
	for (my $i=0;$i<78 ;$i++) {push (@bottomLineBox,205);}
	push (@bottomLineBox,188);

	locate 1,1;
	foreach(@topLineBox)	{printf ("%c",$_);}
	locate 22,1;
	foreach(@dividerLineBox){printf ("%c",$_);}
	locate 24,1;
	foreach(@bottomLineBox)	{printf ("%c",$_);}
	locate 23,1;printf ("%c",186);
	locate 23,80;printf ("%c",186);
	for (my $i=2;$i<22 ;$i++) {
		locate $i,1;
		printf ("%c",186);
		locate $i,80;
		printf ("%c",186);
	}
	locate 23,3;
	return(0);

}

sub enterTestANSIMode{	#command from telnet session: testansi
	for (my $i=0;$i<26 ;$i++) {
		print "\r\n";
	}
	locate 1,1;
	print '@ This is (1,1)';

	locate 5,1;
	print '@ This is (5,1)';
	locate 1,5;
	print '@ This is (1,5)';
	locate 10,10;

#	my ($Xmax,$Ymax)=XYMax();
#	unless ($Xmax) {print "Error Xmax\r\n";	}
#	else {print "Xmax: $Xmax\r\n";}
#	unless ($Ymax) {print "Error Ymax\r\n";	}
#	else {print "Ymax: $Ymax\r\n";}



	print "\r\n";
	return (0);
}


#################
##
##	System Commands
##
sub login{
	my ($queuePointer, $command, $UNPtr)=@_;
	#locate 2,1;print join("\r\n",@$queuePointer);
	if ($command eq 'login') {

		unless (open(CREDS,"auth")) {guiPrint('AUTHENTICATION> SysFailure, can not accept logins at this time',$queuePointer);return(0);}
		locate 5,15;
		printf ("%c",201);
		for (my $i=16;$i<75 ;$i++) {
			locate 5,$i;
			printf ("%c",205);
		}
		locate 5,75;
		printf ("%c",187);
		for (my $i=6;$i<11 ;$i++) {
			locate $i,15;
			print "                                                            ";
			locate $i,15;
			printf ("%c",186);
			locate $i,75;
			printf ("%c",186);
		}
		locate 11,15;
		printf ("%c",200);
		for (my $i=16;$i<75 ;$i++) {
			locate 11,$i;
			printf ("%c",205);
		}
		locate 11,75;
		printf ("%c",188);
		locate 7,17;	
		print "AUTHENTICATION> Please enter your credentials:";
		locate 8,22;
		print "Username: ";
		locate 8,32;
		my $user=getUserIn();
		locate 9,22;
		print "Password: ";
		locate 9,32;
		my $pass=getUserIn();
		while (<CREDS>) {
			chomp;
			my ($ausr,$apass)=split(/\t/,$_);
			#print "auser: $ausr \n";
			#$ausr =~ s/A-Za-z/N-ZA-Mn-za-m/;
			$ausr =~ tr[a-zA-Z][n-za-mN-ZA-M]; 
			$apass =~ tr[a-zA-Z][n-za-mN-ZA-M]; 
			#print "auser: $ausr \n";
			if ($ausr eq $user && $apass eq $pass) {
				$$UNPtr=$user;
				push(@{$queuePointer},"AUTHENTICATION> Login Success.  Thank you $user.");
				return(1);
			}
		}
		push(@{$queuePointer},'AUTHENTICATION> Login Failure, could not find user or invalid password');
#		print "this is a test print";
#		<STDIN>;
#		guiPrint('AUTHENTICATION> Login Failure, could not find user or invalid password',$queuePointer);
		return(0);
	}
	else {	#not command=='login'
		my $tempUser=$$UNPtr;
		$$UNPtr='';
		push(@{$queuePointer},"AUTHENTICATION> " . $tempUser . " has been logged out.");
#		guiPrint("AUTHENTICATION> " . $user . " has been logged out.",$queuePointer);
		return(1);
	}
}
#################
##
##	Test Suite
##
sub dispatchHandlerTest{
	my ($userCredsPtr,$screenBufPtr)=@_;
	my @userCreds=@{$userCredsPtr};
	unless ($userCreds[1]) {guiPrint( "This command unavailable to non-registered users",$screenBufPtr);return(0);}
	while (1) {
		guiPrint( "TEST> Enter command",$screenBufPtr);
		guiPrintPrompt('test>');

		my $input=getUserIn();
		switch ($input){
			case	['ls','list']	{dispatchHandlerTestPrintMenu($screenBufPtr);}
			#case	/^do action /i	{my $command=$input;$command=~s/^do action //i;print "TEST> Doing action: $command\r\n";&doAction($command);}
			#case	/^do test /i	{my $command=$input;$command=~s/^do test //i;print "TEST> Doing test: $command\r\n";&doTest($command);}
			case	/^bye$/i		{guiPrint( "TEST> terminating test session.",$screenBufPtr);return(0);}
			case	'testansi'					{enterTestANSIMode();}
			case	'printscreenbuf'			{locate 2,1;print join("\r\n",@$screenBufPtr); my $foo=<STDIN>;}
			case	'testqueue'					{testQueuePointer($screenBufPtr);}
			case	'screenbuflength'			{push(@$screenBufPtr,scalar(@$screenBufPtr));}
			case	'dumpbuf'					{locate 1,1;require Data::Dumper;print Data::Dumper::Dumper( $screenBufPtr );	<STDIN>	} 
			case	'color'						{locate 3,5;print colored [red], "this is colored RED ";<STDIN>;}
			case	'exit'			{guiPrint( "Exiting test mode.",$screenBufPtr);&guiClearScreen;&guiDrawCleanBox;return(0);}
			#else					{@command=split(/\s+/,$input);&doNaturalAction(\@command);}
			else					{guiPrint( "Invalid command.",$screenBufPtr);}
		}
	}

	return(0);
}
sub dispatchHandlerTestPrintMenu{
	my ($screenBufPtr)=@_;
	guiPrint( "Test Menu:",
		"\ttestansi         enterTestANSIMode()",
		"\tprintscreenbuf   prints the current screenbuffer as array",
		"\ttestqueue        Dumps 10 lines into the screenbuffer",
		"\tscreenbuflength  adds the current screenbuf depth to the buf and prints",
		"\tdumpbuf          prints the current screenbuffer as Data::Dumper",
		"\tcolor            color test",
		"\texit             bail out of tests, re-draws screen",
		$screenBufPtr);
}
sub countDisplay{
	print "12345678901234567890123456789012345678901234567890123456789012345678901234567890\r\n";
	print "2\r\n";
	print "3\r\n";
	print "4\r\n";
	print "5\r\n";
	print "6\r\n";
	print "7\r\n";
	print "8\r\n";
	print "9\r\n";
	print "0\r\n";
	print "1\r\n";
	print "2\r\n";
	print "3\r\n";
	print "4\r\n";
	print "5\r\n";
	print "6\r\n";
	print "7\r\n";
	print "8\r\n";
	print "9\r\n";
	print "0\r\n";

}

############################
##
##	GAMES
##
##
sub playGamesGui{
	my ($userCredsPtr,$ScreenBufPtr)=@_;
	my @localMessageBuffer=();
	my $localMessageBufferPtr=\@localMessageBuffer;
	my @userCreds=@{$userCredsPtr};
	my $menu1Sel=0;
	while (!$menu1Sel) {
		guiPrint( "GAME> would you like to play a game?",$localMessageBufferPtr);
		guiPrintPrompt('GAME>');
		my $input=getUserIn();
		switch ($input){
			case	/^yes$/i	{$menu1Sel=1;}
			case	/^y$/i		{$menu1Sel=1;}
			case	/^bye$/i	{guiPrintMessageQueueToResponseBox('GAME> terminating telnet session.');return('-1');}
			case	/^no$/i		{guiPrintMessageQueueToResponseBox('GAME> you said no, Why did you come here?');push(@$ScreenBufPtr,'GAME> you said no, Why did you come here?') ;return(0);}
			else				{guiPrint( "GAME> a simple yes or no would suffice",$localMessageBufferPtr);}
		}
	}

	$menu1Sel=0;
	while (!$menu1Sel) {
		if ($userCreds[1]) {
			@$localMessageBufferPtr=(	"GAME> What game would you like to play $userCreds[0]?",
												"      1)  Guess a word",
												"      2)  Mad Libs (offline)",
												"      3)  Global Thermonuclear War");
			guiPrintMessageQueueToResponseBox(@$localMessageBufferPtr);
			guiPrintPrompt('GAME>');

			my $input=getUserIn();
			switch ($input){
				case	'1'	{$menu1Sel=1;wordGuessingGame();}
#				case	'2'	{$menu1Sel=2;print MadLibs();;}
				case	'3'	{$menu1Sel=3;&GTW($userCredsPtr);}
				case	'2'	{guiPrint( "GAME> I'm sorry, this game is currently in development",$localMessageBufferPtr);}
#				case	'3'	{guiPrint( "GAME> I'm sorry, this game is currently in development",$localMessageBufferPtr);}
				else		{guiPrint( "GAME> Please enter a valid number from the menu",$localMessageBufferPtr);		}
				#TODO: thermonuclear war, require code red clearance (pwd == Joshua)
			}
		}
		else {
			push(@$ScreenBufPtr, "GAME> Games are currently disabled for non-users");
			return(0);
		}
	}
	return(1);




}

#################
##
##	GTW
## 
sub GTW{
	my ($userCredsPtr)=@_;
	my @GTWMessageBuffer=();
	my $GTWMessageBufferPtr=\@GTWMessageBuffer;

	guiPrint(	"GTW> Hello ${$userCredsPtr}[0] how are you today?",
				"     Shall we play a game?",
				$GTWMessageBufferPtr);
	guiPrintPrompt('GAME>');
	my $input=getUserIn();
	if ($input =~ /Love to. How about Global Thermonuclear War./i || 1) {
		guiPrint( "GTW> Wouldn't you prefer a nice game of chess?",$GTWMessageBufferPtr);
		guiPrintPrompt('GAME>');
		$input=getUserIn();
		if ($input =~ /Later. Right now lets play Global Thermonuclear War./i || 1) {
			guiPrint( "GTW> Fine.",$GTWMessageBufferPtr);
			&_GTWWarGames;
			return(1);
		}
	}

	guiPrint( "GTW> How about a nice game of chess?",$GTWMessageBufferPtr);
	return(0);
	
	switch ($input){
	}
	return(0);

}
sub _GTWWarGames{	#currently takes over the screen to direct draw colors, etc.
	&guiClearResponseBox;
	guiPrintPrompt('LAUNCH MISSLES>');
	my $color='bold red';
	locate 5,15;
	printf ("%c",201);
	for (my $i=16;$i<75 ;$i++) {
		locate 5,$i;
		printf ("%c",205);
	}
	locate 5,75;
	printf ("%c",187);
	for (my $i=6;$i<11 ;$i++) {
		locate $i,15;
		print "                                                            ";
		locate $i,15;
		printf ("%c",186);
		locate $i,75;
		printf ("%c",186);
	}
	locate 11,15;
	printf ("%c",200);
	for (my $i=16;$i<75 ;$i++) {
		locate 11,$i;
		printf ("%c",205);
	}
	locate 11,75;
	printf ("%c",188);
	locate 7,17;	
	print "REDCODE CLEARANCE REQUIRED:";
	locate 8,22;
	print colored [$color],"###>";
	locate 8,27;
	
	
	my $input=getUserIn();
	if ($input eq 'Joshua') {
		#CPE 1704 TKS
		guiPrintPrompt('LAUNCH MISSLES>');
		&_GTWLaunchCodeLoop;
		locate 10,22;print colored [$color],"BANG! you're dead";	
		#&_GTWMushroomCloud;
		<STDIN>;

	}
	return(0);
}
sub _GTWLaunchCodeLoop {
	#print "\r\n";
	my $unMatched=1;
	my $string='CPE 1704 TKS';
	my @lockAry= qw( 0 0 0 0 0 0 0 0 0 0 0 0 );
	my @actualAry=qw( 67 80 69 32 49 55 48 52 32 84 75 83 );
	my $lowerASCIICharBound=32;		
	my $upperASCIICharBound=94;#91		
#	print "DEBUG: @actualAry\n";
	while ($unMatched) {
		my @ary=();
		for (my $i=0;$i < scalar(@actualAry);$i++) {push(@ary,$lowerASCIICharBound+int(rand($upperASCIICharBound-$lowerASCIICharBound)));}
		for (my $i=0;$i < scalar(@actualAry);$i++)	{	if ($ary[$i] == $actualAry[$i]) {$lockAry[$i]=$ary[$i];}	}
		for (my $i=0;$i < scalar(@ary);$i++)		{	if($lockAry[$i])				{$ary[$i]=$lockAry[$i];}	}
		#print "\r";
		#for (my $i=0;$i < scalar(@actualAry);$i++) {print "\b";}
		foreach(@ary){printf ("%c",$_);}
		print "\b\b\b\b\b\b\b\b\b\b\b\b";
		usleep(75000);
		$unMatched=0;
		for (my $i=0;$i < scalar(@actualAry);$i++)	{	unless ($ary[$i] == $actualAry[$i]) {$unMatched=1;}	}
	}

	print "CPE 1704 TKS";
	return(0);
}
sub _GTWMushroomCloud {
	print '';
	usleep(75000);print '      A MUSHROOM CLOUD HAS NO SILVER LINING !!!!!!!!!!!        ', "\r\n";
	usleep(75000);print '                             ____                              ', "\r\n";
	usleep(75000);print '               ____  , -- -        ---   -.                    ', "\r\n";
	usleep(75000);print '            (((   ((  ///   //   \'  \\-\ \  )) ))              ', "\r\n";
	usleep(75000);print '        ///    ///  (( _        _   -- \\--     \\\ \)         ', "\r\n";
	usleep(75000);print '     ((( ==  ((  -- ((             ))  )- ) __   ))  )))       ', "\r\n";
	usleep(75000);print '      ((  (( -=   ((  ---  (          _ ) ---  ))   ))         ', "\r\n";
	usleep(75000);print '         (( __ ((    ()(((  \\  / ///     )) __ )))            ', "\r\n";
	usleep(75000);print '                \\_ (( __  |     | __  ) _ ))                  ', "\r\n";
	usleep(75000);print '                          ,|  |  |                             ', "\r\n";
	usleep(75000);print '                         `-._____,-\'                           ', "\r\n";
	usleep(75000);print '                         `--.___,--\'                           ', "\r\n";
	usleep(75000);print '                           |     |                             ', "\r\n";
	usleep(75000);print '                           |    ||                             ', "\r\n";
	usleep(75000);print '                           | ||  |                             ', "\r\n";
	usleep(75000);print '                 ,    _,   |   | |                             ', "\r\n";
	usleep(75000);print '        (  ((  ((((  /,| __|     |  ))))  )))  )  ))           ', "\r\n";
	usleep(75000);print '      (()))       __/ ||(    ,,     ((//\     )     ))))       ', "\r\n";
	usleep(75000);print '---((( ///_.___ _/    ||,,_____,_,,, (|\ \___.....__..  ))--ool', "\r\n";
	usleep(75000);print '           ____/      |/______________| \/_/\__                ', "\r\n";
	usleep(75000);print '          /                                \/_/|               ', "\r\n";
	usleep(75000);print '         /  |___|___|__                        ||     ___      ', "\r\n";
	usleep(75000);print '         \    |___|___|_                       |/\   /__/|     ', "\r\n";
	usleep(75000);print '         /      |   |                           \/   |__|/     ', "\r\n";
	usleep(75000);print '                                                               ', "\r\n";
	usleep(75000);print '         WELL EXCEPT FOR THE BAD GUYS IT WOULD KILL            ', "\r\n";
	usleep(75000);print '      AND THE FEAR IT WOULD GENERATE IN OTHER BAD GUYS         ', "\r\n";
	usleep(75000);print '                                                               ', "\r\n";
	usleep(75000);print '            OTHER THAN THAT NO SILVER LINING NO                ', "\r\n";

}
#################
##
##	Battleship
## 
sub battleshipGame{
}

#################
##
##	MadLibs
## 
sub MadLibs{
	#The [noun] [past-tense verb] over to [proper noun]
	#and soon [future-tense verb] to the [place].
	guiPrint( "MADLIB> currently off-line");return(0);
	my @Stories=('The [noun] [past tense verb] the [noun]' . "\n" . 'with a [noun] to the [noun]','the [noun] flew by the [adjetive] [noun] like it was [past tense verb] from a [noun]');
	my $story=$Stories[int(rand(scalar(@Stories)- 1))];

	while($story =~ /\[(.*?)\]/g) {   #Find anything in []
	   print "Give me a $1: ";
	   my $val =getUserIn();             #Get a value for it
	   chomp $val;
	   $story =~ s/\[$1\]/$val/;      #And sub it in
	}
	$story =~ s/\n/\r\n/g;
	print $story . "\r\n";
	return(1);
}
#################
##
##	WordGuess
## 
sub wordGuessingGame{
	my @localScreenBuffer=();
	my $lclScrBufPtr=\@localScreenBuffer;

	guiPrint ("WORD> you have selected the word guessing game.",$lclScrBufPtr);
	my $difficultySelect=0;
	while (!$difficultySelect) {
		guiPrint ("WORD> Please select a difficulty level:",
			  "      easy, medium, hard",$lclScrBufPtr);
		guiPrintPrompt('WORD>');
		my $input=getUserIn();
		switch ($input){
			case	/^easy$/i		{$difficultySelect=3;}
			case	['3','e','E']	{$difficultySelect=3;}
			case	/^medium$/i		{$difficultySelect=2;}
			case	['2','m','M']	{$difficultySelect=2;}
			case	/^hard$/i		{$difficultySelect=1;}
			case	['1','h','H']	{$difficultySelect=1;}
			else					{guiPrint( "WORD> invlaid entry",$lclScrBufPtr);guiPrintPrompt('WORD>');}
		}
	}
	guiPrint( "WORD> Selected difficulty level: $difficultySelect",$lclScrBufPtr);
	my @dictionary=qw( technology anthropology physics mathmatics art quandry sociology applied astronomy solar lunar planetary planet asteroid comet probe hubble perl scalar hash array element 
						atom molecule flamethrower fire earth air water henti 
						achieve acquisition alternative analysis approach area aspects assessment assume authority available benefit circumstances comments components concept consistent
						corresponding criteria data deduction demonstrate derived distribution dominant elements equation estimate evaluation factors features final function initial instance
						interpretation journal maintenance method perceived percent period positive potential previous primary principle procedure process range region relevant required
						research resources response role section select significant similar source specific strategies structure theory transfer variables
						Moon
						Mars	Phobos Deimos
						Jupiter	Io Europa Ganymede Callisto Amalthea Himalia Elara Pasiphae Sinope Lysithea Carme Ananke Leda Metis Adrastea Thebe Callirrhoe Themisto Kalyke Iocaste Erinome 
								Harpalyke Isonoe Praxidike Megaclite Taygete Chaldene Autonoe Thyone Hermippe Eurydome Sponde Pasithee Euanthe Kale Orthosie Euporie Aitne
						Saturn	Titan Rhea Iapetus Dione Tethys Enceladus Mimas Hyperion Prometheus Pandora Phoebe Janus Epimetheus Helene Telesto Calypso Atlas Pan Ymir Paaliaq Siarnaq 
								Tarvos Kiviuq Ijiraq Thrym Skadi Mundilfari Erriapo Albiorix Suttung
						Uranus	Cordelia Ophelia Bianca Cressida Desdemona Juliet Portia Rosalind Belinda Puck Miranda Ariel Umbriel Titania Oberon Caliban Sycorax Prospero Setebos Stephano Trinculo
						Neptune	Triton Nereid Naiad Thalassa Despina Galatea Larissa Proteus
						Pluto	Charon
			);
	my $validateGuess=sub{
	};

	for (my $i=0;$i<scalar(@dictionary) ;$i++) {$dictionary[$i]=lc($dictionary[$i]);}
	srand();
	my $pick=int(rand(scalar(@dictionary)));
	my $guesscounter=0;
	my @pick=split(//,lc($dictionary[$pick]));
	my @guess=();
	my @UserGuesses=();
	my $successfulGuess=0;
	guiPrint( "WORD> the word I'm thinking of has " . scalar(@pick) . " letters","      You have " . ($difficultySelect * 5) . " guesses.","      please guess your first letter.",$lclScrBufPtr);
	while ($guesscounter <= ($difficultySelect * 5)) {
		guiPrintPrompt('WORD>');
		my $input=getUserIn();
		my ($guess)=split(//,$input);
		my $alreadyGuessed=0;
		foreach(@UserGuesses){if($guess eq $_){guiPrint( "WORD> you already guessed that, pick another letter please",$lclScrBufPtr);$alreadyGuessed=1;}}
		if ($alreadyGuessed) {next;}
		push(@UserGuesses,$guess);
		my $foundTheGuess=0;
		for (my $offsetCounter=0;$offsetCounter < scalar (@pick) ;$offsetCounter++) {
			if ($pick[$offsetCounter] eq $guess) {
				$guess[$offsetCounter]=$guess;
				$foundTheGuess=1;
				guiPrint( "WORD> Found guess ($guess) at position " . ($offsetCounter + 1) ,$lclScrBufPtr);
				my $currentGuesses='';
				for (my $i=0;$i < scalar (@pick) ;$i++) {
					if ($pick[$i] eq $guess[$i])	{$currentGuesses=$currentGuesses.$guess[$i];}
					else							{$currentGuesses=$currentGuesses.'_';}
				}
				guiPrint( "      Current guesses:     $currentGuesses",$lclScrBufPtr);
			}
			if ($input eq $dictionary[$pick]) {
				guiPrint( "WORD> you guessed the word in " . ($guesscounter+1) . " guesses, congratulations!",$lclScrBufPtr);
				$successfulGuess=1;
				last;
			}
			elsif (join('',@guess) eq $dictionary[$pick]) {
				guiPrint( "WORD> you guessed the word in " . ($guesscounter+1) . " guesses (by brute force), congratulations!",$lclScrBufPtr);
				$successfulGuess=1;
				last;
			}
		}
		unless ($foundTheGuess) {guiPrint( "WORD> Nope, the letter '$guess' is not in the word",$lclScrBufPtr);}
		guiPrint( "WORD> You have " . (($difficultySelect * 5) - $guesscounter) . " guesses remaining",$lclScrBufPtr);
		if ($successfulGuess) {last;}
		$guesscounter++;
	}
	if ($successfulGuess)	{guiPrint( "WORD> Winner!",$lclScrBufPtr);}
	else					{guiPrint( "WORD> Loser :(","      The word was: $dictionary[$pick]",$lclScrBufPtr);}	
	guiPrint( "GAME> Play again?",$lclScrBufPtr);
	guiPrintPrompt('GAME>');
	my $input=getUserIn();
	if (lc($input) eq 'yes' || lc($input) eq 'y') {&wordGuessingGame;}
	return(0);
}

###################################################################################
##LWP HTTP 'Getter'

sub thrExecURLsequencer{
	my ($ptrFIFO,$verbosity)=@_;
	$|=1;

	while (1) {
		my $getCounter=0;
		my $dupCounter=0;
		my $deepURLctr=0;
		my $FailUrlctr=0;
		my @imgs = ();
		my @URLS=();
		my @DEEPURLS=();
		if ($verbosity > 1) {print "sequencer heartbeat\n";}
		unless (scalar(@{$ptrFIFO})) {sleep(5);next;}
		while (scalar(@{$ptrFIFO})) {	push (@URLS,pop(@{$ptrFIFO}));	}
		my $browser = LWP::UserAgent->new;
		$browser->agent( 'Mozilla/4.0 (compatible; MSIE 5.12; Mac_PowerPC)' );
		sub callback {
			my($tag, %attr) = @_;
			#print "$tag\n";
			return if lc($tag) ne 'a';  # we  look closer at <a ...>
			foreach my $value (values %attr) {
				if		($value =~ /\.(jpg|jpeg|wmv|mpg|avi|mpeg|mp3|oog|mkv|mov|hdmov|flv|flac|wav|wma|divx|xvid|mp4)$/i) {push(@imgs,$value);}
				elsif	($value =~ /\.(htm|html|shtml)/i)  {push(@DEEPURLS,$value);if ($verbosity > 0) {print "Deep URL\n";};$deepURLctr++;}
			}
		}
		sub callback_d {
			my($tag, %attr) = @_;
			#print "$tag\n";
			return if lc($tag) ne 'img';  # we only look closer at <img ...>
			push (@imgs,values %attr);
		}
		if ($verbosity > 0) {print "getting inital URLs...\n";}
		foreach my $url (@URLS) {
			@imgs = ();
			my $response = $browser->get($url);
			$FailUrlctr++, $response->status_line unless $response->is_success;
			# Make the parser.  Unfortunately, we don't know the base yet
			# (it might be diffent from $url)
			my $p = HTML::LinkExtor->new(\&callback);
			# Request document and parse it as it arrives
			my $res = $browser->request(HTTP::Request->new(GET => $url), sub {$p->parse($_[0])});
			# Expand all image URLs to absolute ones
			my $base = $res->base;
			@imgs = map { $_ = url($_, $base)->abs; } @imgs;
			@DEEPURLS = map { $_ = url($_, $base)->abs; } @DEEPURLS;
			# Print them out
			#print join("\n", @imgs), "\n";
			foreach my $imgUrl (@imgs) {
				my $imageFile=$imgUrl;
				$imageFile=~s/http:\/\///;
				if (-e './' . $imageFile) {if ($verbosity > 0) {print "FILE EXISIS, Skipping\n";};	$dupCounter++; next;}
				if ($imageFile =~ /(.+)\/\w+\.(jpg|jpeg|wmv|mpg|avi|mpeg|mp3|oog|mkv|mov|hdmov|flv|flac|wav|wma|divx|xvid)$/i) {mkpath($1);}
				eval {$browser->mirror($imgUrl,'./' . $imageFile);};
				if ($@) {if ($verbosity > 0) {print "Eval Error\n";};$FailUrlctr++;}
				print "File\n";
				$getCounter++;
			}
		}
		if ($verbosity > 0) {print "getting deep URLs...\n";}
		foreach my $url (@DEEPURLS) {
			@imgs = ();
			#print $url;
			my $response = $browser->get($url);
			$FailUrlctr++, $response->status_line unless $response->is_success;
			#print "\nresponse: ";
			#print Dumper $response;
			# Make the parser.  Unfortunately, we don't know the base yet
			# (it might be diffent from $url)
			my $p = HTML::LinkExtor->new(\&callback_d);
			# Request document and parse it as it arrives
			my $res = $browser->request(HTTP::Request->new(GET => $url), sub {$p->parse($_[0])});
			# Expand all image URLs to absolute ones
			my $base = $res->base;
			@imgs = map { $_ = url($_, $base)->abs; } @imgs;
			# Print them out
			#print join("\n", @imgs), "\n";
			foreach my $imgUrl (@imgs) {
				my $imageFile=$imgUrl;
				$imageFile=~s/http:\/\///;
				if (-e './' . $imageFile) {if ($verbosity > 0) {print "FILE EXISIS, Skipping\n";};	$dupCounter++; next;}
				if ($imageFile =~ /(.+)\/\w+\.(jpg|jpeg|wmv|mpg|avi|mpeg|mp3|oog|mkv|mov|hdmov|flv|flac|wav|wma|divx|xvid|mp4)$/i) {mkpath($1);}
				eval{$browser->mirror($imgUrl,'./' . $imageFile);};
				if ($@) {if ($verbosity > 0) {print "Eval Error\n";};$FailUrlctr++;}
				if ($verbosity > 0) {print "File\n";}
				$getCounter++;
			}
		}
		if ($verbosity > 0) {
				print "got:  $getCounter\n";
				print "skip: $dupCounter\n";
				print "deep: $deepURLctr\n";
				print "fail: $FailUrlctr\n";
		}
	}
}





__END__
###################################################################################

