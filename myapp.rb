# myapp.rb
require 'sinatra'
require 'instagram'
require 'rubygems'
require 'pp'
require 'dropbox_sdk'
require 'open-uri'
require 'net/https'
require 'cgi'
require 'json'

enable :sessions
set :public_folder, File.dirname(__FILE__) + '/static'

##### CONFIGURATION VARIABLES

### INSTAGRAM

CALLBACK_URL = "http://localhost:4567/oauth/callback"

Instagram.configure do |config|
  config.client_id = "2530a996b6044d9eb624b9960bbd2ede"
  config.client_secret = "001c3a647b264376a08ce6a4be30f070"
end

### DROPBOX

APP_KEY = 'zz6p2c60mzz5do9'
APP_SECRET = 'tc4dklqwxuy6cqr'
ACCESS_TYPE = :app_folder

##### APP START

get "/" do
  erb :start
end

##### INSTAGRAM AUTH

get "/oauth/connect" do
  redirect Instagram.authorize_url(:redirect_uri => CALLBACK_URL)
end

get "/oauth/callback" do
  response = Instagram.get_access_token(params[:code], :redirect_uri => CALLBACK_URL)
  session[:access_token] = response.access_token
  redirect "/likes"
end

##### INSTAGRAM PULL
get "/likes" do
  client = Instagram.client(:access_token => session[:access_token])
  user = client.user
  my_likes = []
  @username = user.username
  @thumbnails = []
  client.user_liked_media["data"].each do |media_item|
    short_tag = media_item.images.standard_resolution.url.split('/')[-1]
    tmp_url = File.dirname(__FILE__).to_s + "/tmp/#{short_tag}"
    open(media_item.images.standard_resolution.url) {|f|
      File.open(tmp_url, "wb") do |file|
        file.puts f.read
      end
    }
    my_likes.push(tmp_url)
    @thumbnails.push (media_item.images.thumbnail.url)     
  end
  session[:my_likes] = my_likes
  @any_likes = false
  if my_likes.length != 0
    @any_likes = true
  end
  erb :likes
end

##### DROPBOX AUTH

get '/oauth-start' do
    db_session = DropboxSession.new(APP_KEY, APP_SECRET)
    begin
        db_session.get_request_token
    rescue DropboxError => e
        return html_page "Exception in OAuth step 1", "<p>#{h e}</p>"
    end

    session[:request_db_session] = db_session.serialize

    auth_url = db_session.get_authorize_url url('/oauth-callback')
    redirect auth_url 
end

get '/oauth-callback' do
    ser = session[:request_db_session]
    unless ser
        return html_page "Error in OAuth step 2", "<p>Couldn't find OAuth state in session.</p>"
    end
    db_session = DropboxSession.deserialize(ser)

    begin
        db_session.get_access_token
    rescue DropboxError => e
        return html_page "Exception in OAuth step 3", "<p>#{h e}</p>"
    end
    session.delete(:request_db_session)
    session[:authorized_db_session] = db_session.serialize
    redirect url('/dropbox')
end

def get_db_client
    if session[:authorized_db_session]
        db_session = DropboxSession.deserialize(session[:authorized_db_session])
        begin
            return DropboxClient.new(db_session, ACCESS_TYPE)
        rescue DropboxAuthError => e
            session[:authorized_db_session].delete
        end
    end
end

get '/dropbox' do
    db_client = get_db_client
    unless db_client
        redirect url("/oauth-start")
    end

    path = params[:path] || '/'
    begin
        entry = db_client.metadata(path)
    rescue DropboxAuthError => e
        session.delete(:authorized_db_session)
        return html_page "Dropbox auth error", "<p>#{h e}</p>"
    rescue DropboxError => e
        if e.http_response.code == '404'
            return html_page "Path not found: #{h path}", ""
        else
            return html_page "Dropbox API error", "<p>#{h e.http_response}</p>"
        end
    end
    redirect url("/upload")
end

##### DROPBOX UPLOAD

get '/upload' do
    likes = session[:my_likes]
    if likes.length == 0
        return html_page "Upload error", "<p>No images to save!</p>"
    end
    db_client = get_db_client
    unless db_client
        return html_page "Upload error", "<p>Not linked with a Dropbox account.</p>"
    end
    likes.each do |image|
      begin
          new_name = image.split('/')[-1]
          entry = db_client.put_file("/#{new_name}", open(image))
          File.delete(File.dirname(__FILE__).to_s + "/tmp/#{new_name}")
      rescue DropboxAuthError => e
          session.delete(:authorized_db_session)
          return html_page "Dropbox auth error", "<p>#{h e}</p>"
      rescue DropboxError => e
          return html_page "Dropbox API error", "<p>#{h e}</p>"
      end
    end
    erb :success
end

get '/*' do
  erb :oops
end

# -------------------------------------------------------------------
helpers do
    include Rack::Utils
    alias_method :h, :escape_html
end

__END__
@@ layout
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>Dropstagram</title>

<link rel="stylesheet" href="/css/reset.css" type="text/css"> 
<link rel="stylesheet" href="/css/stylesheet.css" type="text/css"> 

</head>
  <body>
    <div>
        <h1>
        	<div id='logo'> 
    	     <img src="/assets/logo.png"/>
        	</div>
        </h1>

    </div>
   <%= yield %>
  </body>
</html>

@@ start
<p><a href="/oauth/connect" class="button">Connect with Instagram</a></p>

@@ likes
<p>
<% for @item in @thumbnails %>
  <img src='<%= @item %>'>
<% end %>
<% if @any_likes%>
  <a href="../dropbox" class="button">Save to Dropbox</a>
<% else %> 
  <div>You have not liked any photos</div><br />
<% end %>
</p>
@@ success
<p>You successfully uploaded your Instagram likes to Dropbox</p>

@@ oops
<p>Oops wrong url!</p>


