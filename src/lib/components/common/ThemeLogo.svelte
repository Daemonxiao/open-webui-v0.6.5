<script lang="ts">
	import { WEBUI_BASE_URL } from '$lib/constants';

	export let className = '';
	export let alt = 'logo';
	export let draggable: boolean | undefined = false;
	export let crossorigin: 'anonymous' | 'use-credentials' | undefined = 'anonymous';
	export let loading: 'eager' | 'lazy' | undefined = undefined;
	export let fetchpriority: 'high' | 'low' | 'auto' | undefined = undefined;

	const lightSrc = `${WEBUI_BASE_URL}/static/favicon-light.png`;
	const darkSrc = `${WEBUI_BASE_URL}/static/favicon-dark.png`;
</script>

<img
	src={lightSrc}
	class="{className} dark:hidden"
	{alt}
	{draggable}
	{crossorigin}
	{loading}
	{fetchpriority}
/>
<img
	src={darkSrc}
	class="{className} hidden dark:block"
	{alt}
	{draggable}
	{crossorigin}
	{loading}
	{fetchpriority}
/>
