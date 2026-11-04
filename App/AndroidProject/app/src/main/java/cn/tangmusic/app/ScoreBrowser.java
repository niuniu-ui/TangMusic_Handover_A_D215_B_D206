package cn.tangmusic.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.net.Uri;
import android.view.ViewGroup;
import android.webkit.*;
import android.widget.*;
import java.util.Locale;
import java.util.function.Consumer;

/** A separate website view: MIDI selections return to the existing import pipeline. */
final class ScoreBrowser {
    private Dialog dialog;private WebView browser;
    static final String HOME="https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano";
    static String allowed(String value){
        try{Uri uri=Uri.parse(value);String host=uri.getHost();if(host==null||!(host.equalsIgnoreCase("www.mutopiaproject.org")||host.equalsIgnoreCase("mutopiaproject.org"))||uri.getUserInfo()!=null||uri.getPort()!=-1)return null;
            if(!"https".equalsIgnoreCase(uri.getScheme())&&!"http".equalsIgnoreCase(uri.getScheme()))return null;
            return uri.buildUpon().scheme("https").build().toString();
        }catch(Exception e){return null;}
    }
    @SuppressLint("SetJavaScriptEnabled")
    void open(Activity activity,Consumer<String> selected){
        if(dialog!=null&&dialog.isShowing())return;
        dialog=new Dialog(activity);LinearLayout layout=new LinearLayout(activity);layout.setOrientation(LinearLayout.VERTICAL);layout.setBackgroundColor(Color.rgb(245,245,231));
        LinearLayout toolbar=new LinearLayout(activity);Button back=new Button(activity),home=new Button(activity),close=new Button(activity);back.setText("上一页");home.setText("曲谱首页");close.setText("返回曲库");
        for(Button button:new Button[]{back,home,close})toolbar.addView(button,new LinearLayout.LayoutParams(0,ViewGroup.LayoutParams.WRAP_CONTENT,1));
        TextView status=new TextView(activity);status.setText("Mutopia 曲谱网站 · 点击 .mid / MIDI 文件即可下载并适配");status.setPadding(20,12,20,12);
        browser=new WebView(activity);WebSettings settings=browser.getSettings();settings.setJavaScriptEnabled(false);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setBuiltInZoomControls(true);settings.setDisplayZoomControls(false);
        browser.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                if(!request.isForMainFrame())return false;
                String url=allowed(request.getUrl().toString());if(url==null){status.setText("请在 Mutopia 曲谱站内选择 MIDI 文件。");return true;}
                String path=Uri.parse(url).getPath();if(path!=null&&path.toLowerCase(Locale.ROOT).matches(".*\\.(mid|midi)$")){close();selected.accept(url);return true;}
                if(path!=null&&path.toLowerCase(Locale.ROOT).matches(".*\\.(pdf|ps|gz|zip|ly|png|svg)$")){status.setText("请选择 .mid / MIDI 文件，下载后才能选段并做琴键引导。");return true;}
                if(!url.equals(request.getUrl().toString())){view.loadUrl(url);return true;}return false;
            }
            @Override public void onPageStarted(WebView view,String url,android.graphics.Bitmap icon){status.setText("正在加载 Mutopia 曲谱网站…");}
            @Override public void onPageFinished(WebView view,String url){status.setText("点击曲目进入详情，选择 .mid / MIDI file 下载并适配。");}
            @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){if(request.isForMainFrame())status.setText("网站暂时无法打开，请检查网络或点击曲谱首页重试。");}
        });
        browser.setDownloadListener((url,agent,disposition,mime,size)->{
            String checked=allowed(url),path=checked==null?null:Uri.parse(checked).getPath();
            if(checked!=null&&((path!=null&&path.toLowerCase(Locale.ROOT).matches(".*\\.(mid|midi)$"))||"audio/midi".equals(mime)||"audio/x-midi".equals(mime))){close();selected.accept(checked);}else status.setText("请选择 .mid / MIDI 文件下载。");
        });
        back.setOnClickListener(v->{if(browser.canGoBack())browser.goBack();});home.setOnClickListener(v->browser.loadUrl(HOME));close.setOnClickListener(v->close());
        layout.addView(toolbar);layout.addView(status);layout.addView(browser,new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,0,1));dialog.setContentView(layout);
        dialog.setOnDismissListener(d->{if(browser!=null){browser.stopLoading();if(browser.getParent() instanceof ViewGroup parent)parent.removeView(browser);browser.destroy();browser=null;}dialog=null;});
        dialog.show();dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.MATCH_PARENT);browser.loadUrl(HOME);
    }
    void close(){if(dialog!=null)dialog.dismiss();}
}
