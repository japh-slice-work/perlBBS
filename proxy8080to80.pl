use Net::Proxy;

# proxy connections from localhost:6789 to remotehost:9876
# using standard TCP connections
my $proxy = Net::Proxy->new(
    {   in  => { type => 'tcp', host => '10.19.232.123', port => '8080' },
        out => { type => 'tcp', host => '192.168.49.121', port => '80' },
    }
);
my $proxy2 = Net::Proxy->new(
    {   in  => { type => 'tcp', host => '10.19.232.123', port => '8088' },
        out => { type => 'tcp', host => '192.168.49.121', port => '80' },
    }
);

# register the proxy object
$proxy->register();
$proxy2->register();

# and you can setup multiple proxies

# and now proxy connections indefinitely
Net::Proxy->mainloop();