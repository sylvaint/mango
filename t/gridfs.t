use Mojo::Base -strict;

use Test::More;
use Mango;
use Mojo::IOLoop;

plan skip_all => 'set TEST_ONLINE to enable this test'
  unless $ENV{TEST_ONLINE};

# Clean up before start
my $mango  = Mango->new($ENV{TEST_ONLINE});
my $gridfs = $mango->db->gridfs;
$gridfs->$_->remove for qw(files chunks);

# Blocking roundtrip
my $writer = $gridfs->writer;
$writer->filename('foo.txt')->content_type('text/plain');
$writer->write('hello ');
$writer->write('world!');
my $oid    = $writer->close;
my $reader = $gridfs->reader;
$reader->open($oid);
is $reader->filename,     'foo.txt',    'right filename';
is $reader->content_type, 'text/plain', 'right content type';
is $reader->size,         12,           'right size';
is $reader->chunk_size,   262144,       'right chunk size';
is length $reader->upload_date, length(time) + 3, 'right time format';
my $data;
while (defined(my $chunk = $reader->read)) { $data .= $chunk }
is $data, 'hello world!', 'right content';
is_deeply $gridfs->list, ['foo.txt'], 'right files';
$gridfs->delete($oid);
is_deeply $gridfs->list, [], 'no files';
$gridfs->$_->drop for qw(files chunks);

# Non-blocking roundtrip
$writer = $gridfs->writer->chunk_size(4);
$writer->filename('foo.txt')->content_type('text/plain');
my ($fail, $result);
my $delay = Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    $writer->write('he' => $delay->begin);
  },
  sub {
    my ($delay, $err) = @_;
    $fail = $err;
    $writer->write('llo ' => $delay->begin);
  },
  sub {
    my ($delay, $err) = @_;
    $fail ||= $err;
    $writer->write('w'     => $delay->begin);
    $writer->write('orld!' => $delay->begin);
  },
  sub {
    my ($delay, $err) = @_;
    $fail ||= $err;
    $writer->close($delay->begin);
  },
  sub {
    my ($delay, $err, $oid) = @_;
    $fail ||= $err;
    $result = $oid;
  }
);
$delay->wait;
ok !$mango->is_active, 'no operations in progress';
ok !$fail, 'no error';
$oid    = $result;
$reader = $gridfs->reader;
($fail, $result) = ();
$delay = Mojo::IOLoop->delay(
  sub { $reader->open($oid => shift->begin) },
  sub {
    my ($delay, $err) = @_;
    $fail = $err;
  }
);
$delay->wait;
ok !$mango->is_active, 'no operations in progress';
ok !$fail, 'no error';
is $reader->filename,     'foo.txt',    'right filename';
is $reader->content_type, 'text/plain', 'right content type';
is $reader->size,         12,           'right size';
is $reader->chunk_size,   4,            'right chunk size';
is length $reader->upload_date, length(time) + 3, 'right time format';
$data = undef;
while (defined(my $chunk = $reader->read)) { $data .= $chunk }
is $data, 'hello world!', 'right content';
is_deeply $gridfs->list, ['foo.txt'], 'right files';
$gridfs->delete($oid);
is_deeply $gridfs->list, [], 'no files';
$gridfs->$_->drop for qw(files chunks);

done_testing();
