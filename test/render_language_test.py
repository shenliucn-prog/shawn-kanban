import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('renderer', Path(__file__).parents[1] / 'tools/render_screen.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

class LanguageTests(unittest.TestCase):
    def tearDown(self):
        r.LANG = 'zh'

    def test_english_content_and_chinese_payload_are_independent(self):
        data = {'news': {'items': [{'title': '中文新闻'}]}, 'newsEn': {'items': [{'title': 'English news'}]},
                'weather': {'city': '深圳', 'code': 0, 'text': '晴'},
                'stocks': {'items': [{'sym': 'AAPL', 'label': '苹果'}]},
                'clocks': {'items': [{'city': '伦敦', 'tz': 'Europe/London', 'date': '09/11周五'}]},
                'mlb': {'items': [{'abbr': 'LAD', 'cn': '道奇', 'next': {'opp': '教士', 'live': True}}]}}
        r.LANG = 'en'
        en = r.localized_data(data)
        self.assertEqual(en['news']['items'][0]['title'], 'English news')
        self.assertEqual(en['weather']['text'], 'Clear')
        self.assertEqual(en['weather']['city'], 'Shenzhen')
        self.assertEqual(en['stocks']['items'][0]['label'], 'AAPL')
        self.assertEqual(en['clocks']['items'][0]['city'], 'London')
        self.assertEqual(en['mlb']['items'][0]['next']['opp'], 'SD')
        self.assertEqual(en['mlb']['items'][0]['next']['time'], 'Live')
        self.assertEqual(r.tr('世界时钟'), 'World Clocks')
        r.LANG = 'zh'
        self.assertEqual(r.localized_data(data), data)
        self.assertEqual(data['weather']['text'], '晴')
        self.assertEqual(r.tr('世界时钟'), '世界时钟')

    def test_missing_english_feed_does_not_show_chinese_headlines(self):
        r.LANG = 'en'
        self.assertEqual(r.localized_data({'news': {'items': [{'title':'中文'}]}})['news']['items'], [])
        self.assertTrue(all(line.isascii() for line in r.load_quotes()))
