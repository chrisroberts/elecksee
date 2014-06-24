describe Lxc do
  describe Pathname do
    it 'should join properly when suffix params contain leading slash' do
      Lxc::Pathname.new('/tmp').join('/fubar').to_s.
        must_equal '/tmp/fubar'
      Lxc::Pathname.new('/tmp').join('fubar', '/foobar').to_s.
        must_equal('/tmp/fubar/foobar')
    end
  end

  describe 'ClassMethods' do
    describe 'sudo' do
      it 'should not provide sudo command by default' do
        Lxc.use_sudo = nil
        Lxc.sudo.must_be_nil
      end
      it 'should provide default command when true' do
        Lxc.use_sudo = true
        Lxc.sudo.must_equal 'sudo '
      end
      it 'should provide custom command when set' do
        Lxc.use_sudo = 'rvmsudo'
        Lxc.sudo.must_equal 'rvmsudo '
      end
    end

    describe 'state information' do
      before do
        Lxc.use_sudo = 'rvmsudo'
      end
      it 'should include running test container' do
        Lxc.running.must_include 'elecksee-tester-3'
      end
      it 'should include stopped test container' do
        Lxc.stopped.must_include 'elecksee-tester-0'
      end
      it 'should include frozen test container' do
        Lxc.frozen.must_include 'elecksee-tester-1'
      end
      it 'should show existing container as existing' do
        Lxc.exists?('elecksee-tester-1').must_equal true
      end
      it 'should show non-existing container as not existing' do
        Lxc.exists?('90290fw9f0w').must_equal false
      end
      it 'should provide information about running container' do
        info = Lxc.info('elecksee-tester-3')
        info[:state].must_equal :running
        info[:pid].must_be_kind_of Integer
      end
      it 'should provide information about stopped container' do
        info = Lxc.info('elecksee-tester-0')
        info[:state].must_equal :stopped
      end
      it 'should provide unknown information about unknown container' do
        info = Lxc.info('099029fj0')
        info[:state].must_equal :unknown
        info[:pid].must_equal -1
      end

    end

    it 'should provide default base path' do
      Lxc.base_path.must_equal '/var/lib/lxc'
    end
  end

  describe 'Running container' do
    before do
      Lxc.use_sudo = 'rvmsudo'
      @lxc = Lxc.new('elecksee-tester-3')
    end
    let(:lxc){ @lxc }

    describe 'Container state' do
      it 'should be running' do
        lxc.running?.must_equal true
      end
      it 'should not be stopped' do
        lxc.stopped?.must_equal false
      end
      it 'should not be frozen' do
        lxc.frozen?.must_equal false
      end
      it 'should exist' do
        lxc.exists?.must_equal true
      end
      it 'should have an IP adddress' do
        lxc.container_ip(5).must_be_kind_of String
        lxc.container_ip.wont_be_empty
      end
      it 'should return running state' do
        lxc.state.must_equal :running
      end
    end

    describe 'Container information' do
      it 'should provide the container path' do
        lxc.container_path.to_path.wont_be_empty
      end
      it 'should provide the config path' do
        lxc.container_config.to_path.wont_be_empty
      end
      it 'should provide the rootfs path' do
        lxc.container_rootfs.to_path.wont_be_empty
      end
      it 'should expand relative paths from the rootfs' do
        lxc.expand_path('tmp/my_file').to_path.must_equal File.join(
          lxc.container_rootfs.to_path, 'tmp/my_file'
        )
      end
      it 'should provide the containers pid' do
        lxc.pid.must_be_kind_of Numeric
      end
    end

    describe 'Change container state' do
      it 'should stop and start the container' do
        lxc.stop
        lxc.stopped?.must_equal true
        lxc.start
        lxc.running?.must_equal true
      end
      it 'should freeze and thaw the container' do
        lxc.freeze
        lxc.frozen?.must_equal true
        lxc.unfreeze
        lxc.running?.must_equal true
      end
    end

    describe 'Running commands' do
      it 'should allow commands executed within it' do
        lxc.container_command('ls /').stdout.split("\n").must_include 'tmp'
      end
    end
  end

  describe 'Stopped container' do
    before do
      @lxc = Lxc.new('elecksee-tester-0')
    end
    let(:lxc){ @lxc }

    it 'should allow commands executed within it' do
      lxc.execute('ls').stdout.split("\n").must_include 'tmp'
    end
  end

  describe 'State waiter' do
    before do
      @lxc = Lxc.new('elecksee-tester-3')
    end
    let(:lxc){ @lxc }

    describe 'when stopped' do
      before do
        lxc.stop
        Thread.new do
          sleep(0.5)
          Lxc.new('elecksee-tester-3').start
        end
      end

      it 'should wait for running state' do
        lxc.wait_for_state(:running)
        lxc.running?.must_equal true
      end
    end
  end

end
