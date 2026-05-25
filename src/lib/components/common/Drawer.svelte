<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { flyAndScale } from '$lib/utils/transitions';
	import { fade, fly, slide } from 'svelte/transition';

	export let show = false;
	export let className = '';
	export let side: 'bottom' | 'right' = 'bottom';
	export let onClose = () => {};

	let modalElement = null;
	let mounted = false;

	const handleKeyDown = (event: KeyboardEvent) => {
		if (event.key === 'Escape' && isTopModal()) {
			console.log('Escape');
			show = false;
		}
	};

	const isTopModal = () => {
		const modals = document.getElementsByClassName('modal');
		return modals.length && modals[modals.length - 1] === modalElement;
	};

	onMount(() => {
		mounted = true;
	});

	$: if (show && modalElement) {
		document.body.appendChild(modalElement);
		window.addEventListener('keydown', handleKeyDown);
		document.body.style.overflow = 'hidden';
	} else if (modalElement) {
		onClose();
		window.removeEventListener('keydown', handleKeyDown);

		if (document.body.contains(modalElement)) {
			document.body.removeChild(modalElement);
			document.body.style.overflow = 'unset';
		}
	}

	onDestroy(() => {
		window.removeEventListener('keydown', handleKeyDown);
		show = false;
		if (modalElement) {
			if (document.body.contains(modalElement)) {
				document.body.removeChild(modalElement);
				document.body.style.overflow = 'unset';
			}
		}
	});
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
{#if show}
	<div
		bind:this={modalElement}
		class="modal fixed right-0 bottom-0 left-0 top-0 z-999 flex h-screen max-h-[100dvh] w-full overflow-hidden overscroll-contain bg-black/60 {side ===
		'right'
			? 'justify-end'
			: 'justify-center'}"
		in:fade={{ duration: 100 }}
		on:mousedown={() => {
			show = false;
		}}
	>
		<div
			class="{side === 'right'
				? 'ml-auto h-full max-h-[100dvh]'
				: 'mt-auto w-full max-h-[100dvh]'} bg-gray-50 dark:bg-gray-900 dark:text-gray-100 {className} scrollbar-hidden overflow-y-auto"
			in:fly={side === 'right' ? { x: 100, duration: 150 } : { y: 100, duration: 100 }}
			on:mousedown={(e) => {
				e.stopPropagation();
			}}
		>
			<slot />
		</div>
	</div>
{/if}

<style>
	.modal-content {
		animation: scaleUp 0.1s ease-out forwards;
	}

	@keyframes scaleUp {
		from {
			transform: scale(0.985);
			opacity: 0;
		}
		to {
			transform: scale(1);
			opacity: 1;
		}
	}
</style>
